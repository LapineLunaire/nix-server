{
  config,
  dmz,
  net,
  trustedSubnets,
  pkgs,
  ...
}: let
  # The router repeats LAN discovery with its own source address.
  discoverySources = [trustedSubnets.lan dmz.gateway];
  discoverySourcesNft = builtins.concatStringsSep ", " discoverySources;
in {
  imports = [
    ../../../../modules/nixos/zfs.nix
    ./samba.nix
    ./sops.nix
  ];

  host.trustedSubnets = trustedSubnets.all;

  microvm = {
    vcpu = 4;
    mem = 8192;
    # Use fixed memory so balloon reclamation does not compete with ZFS ARC.
    balloon = false;
    devices = [
      {
        # SAS3008, isolated in IOMMU group 16; microvm.nix binds it to VFIO.
        bus = "pci";
        path = "0000:01:00.0";
      }
    ];
    # Keep PCI BARs within the 39-bit VT-d aperture.
    cloud-hypervisor.extraArgs = ["--cpus" "max_phys_bits=39"];
  };

  # Load the HBA driver after boot; the vault pool is not a root filesystem.
  boot.kernelModules = ["mpt3sas"];

  # Keep the guest's ZFS host ID distinct from Sparkle's.
  networking.hostId = "4e9d7c21";

  boot.extraModprobeConfig = "options zfs zfs_arc_max=4294967296";

  # Mount only after vault-unlock loads the key. NFS and Samba pull in their required mounts.
  fileSystems = let
    dataset = name: {
      device = "vault/${name}";
      fsType = "zfs";
      options = [
        "zfsutil"
        "noauto"
        "x-systemd.requires=vault-unlock.service"
      ];
    };
  in {
    "/vault/carmilla" = dataset "carmilla";
    "/vault/misc" = dataset "misc";
    "/vault/misc/library" = dataset "misc/library";
    "/vault/torrents" = dataset "torrents";
  };

  # Import without prompting; vault-unlock supplies the key before mounting.
  boot.zfs.requestEncryptionCredentials = false;

  # Match the host bridge's source restrictions.
  networking.firewall.extraInputRules = ''
    ip saddr { ${net.nfsClientsNft} } tcp dport ${toString net.nfsPort} accept
    ip saddr { ${config.host.trustedSubnetsNft} } tcp dport { 139, 445 } accept
    ip saddr { ${discoverySourcesNft} } udp dport { 137, 138 } accept
    ip saddr { ${discoverySourcesNft} } tcp dport 5357 accept
    ip daddr 224.0.0.251 udp dport 5353 accept
    ip daddr 239.255.255.250 udp dport 3702 accept
  '';

  # Discovery replies need separate flows for new conntrack tuples.
  # wsdd replies from port 3702 to the LAN client or its router.
  microvmGuest.egress = [
    {
      proto = "tcp";
      ports = [587];
    }
    {
      proto = "udp";
      ports = [5353];
      destinations = ["224.0.0.251"];
    }
    {
      proto = "udp";
      ports = [3702];
      destinations = ["239.255.255.250"];
    }
    {
      proto = "udp";
      sourcePorts = [3702];
      destinations = discoverySources;
    }
  ];

  # Only this guest can monitor the passed-through disks.
  services.smartd = {
    enable = true;
    notifications.mail = {
      enable = true;
      sender = "noreply@lunaire.eu";
      recipient = "carmilla@lunaire.eu";
    };
  };
  # smartd references smartmontools but does not add smartctl to PATH.
  environment.systemPackages = [pkgs.smartmontools];

  programs.msmtp = {
    enable = true;
    setSendmail = true;
    accounts.default = {
      host = "smtp.protonmail.ch";
      port = "587";
      user = "noreply@lunaire.eu";
      auth = true;
      tls = true;
      from = "noreply@lunaire.eu";
      passwordeval = "cat ${config.sops.secrets."smartd-smtp-password".path}";
    };
  };

  # Squash NFS writes to the torrents account.
  users.groups.torrents.gid = 3000;
  users.users.torrents = {
    isSystemUser = true;
    uid = 3000;
    group = "torrents";
    description = "Owner of the torrents dataset";
  };

  # Serve NFSv4 only. Squash client-supplied UIDs to each export's owner.
  # An explicitly exported child needs both clients; crossmnt only inherits access for implicit exports.
  services.nfs.server = {
    enable = true;
    exports = ''
      /vault/misc ${net.vmAddress.proxy}(ro,sec=sys,no_subtree_check,crossmnt,all_squash,anonuid=1000,anongid=100)
      /vault/misc/library ${net.vmAddress.proxy}(ro,sec=sys,no_subtree_check,all_squash,anonuid=1000,anongid=100) ${net.vmAddress.kavita}(ro,sec=sys,no_subtree_check,all_squash,anonuid=1000,anongid=100)
      /vault/torrents ${net.vmAddress.qbittorrent}(rw,sync,sec=sys,no_subtree_check,all_squash,anonuid=3000,anongid=3000)
    '';
  };

  services.nfs.settings.nfsd = {
    vers2 = false;
    vers3 = false;
    udp = false;
  };

  systemd.services.nfs-server.unitConfig.RequiresMountsFor = [
    "/vault/misc"
    "/vault/misc/library"
    "/vault/torrents"
  ];

  # Supply the key location for this load only; keep the pool's recovery prompt.
  systemd.services.vault-unlock = {
    description = "Load the vault pool's encryption key";
    requires = ["zfs-import-vault.service"];
    after = ["zfs-import-vault.service"];
    before = ["shutdown.target"];
    conflicts = ["shutdown.target"];
    # Run before local-fs.target without the default ordering after basic.target.
    # SOPS installs the key during activation, before systemd starts.
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "vault-unlock" ''
        set -eu
        zfs=${config.boot.zfs.package}/sbin/zfs
        # Idempotent: a restarted unit must not fail on a key that is already loaded.
        if [ "$($zfs get -H -o value keystatus vault)" = available ]; then
          exit 0
        fi
        exec $zfs load-key -L file://${config.sops.secrets."vault-zfs-key".path} vault
      '';
    };
  };
}
