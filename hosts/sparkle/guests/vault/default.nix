# Storage for the guests: the SAS HBA passed through by VFIO, the vault pool imported and unlocked here, and its datasets served to the guests over NFSv4 and to the clients over SMB.
{
  config,
  dmz,
  net,
  trustedSubnets,
  outputs,
  pkgs,
  ...
}: let
  # Who may reach the discovery services, and who a discovery reply may go back to. Browsing is link-local, so this covers the LAN, the one client network attached to the router that repeats mDNS and WS-Discovery. A VPN or off-site client mounts a share by name.
  # The router is listed separately because its repeater re-emits the LAN's multicast with its own address. If browsing from the LAN stops working, that address is the thing to check.
  discoverySources = [trustedSubnets.lan dmz.gateway];
  discoverySourcesNft = builtins.concatStringsSep ", " discoverySources;
in {
  imports = [
    # Scrub, trim and autosnapshot follow the pool into whichever system imports it.
    outputs.nixosModules.zfs
    ./samba.nix
    ./sops.nix
  ];

  # Read as the option by Samba's hosts allow and the input chain below, and as the binding by the discovery reply in the egress declaration. From trusted-subnets.nix, so it cannot drift from sparkle's copy or the proxy's.
  host.trustedSubnets = trustedSubnets.all;

  microvm = {
    vcpu = 4;
    mem = 8192;
    # ARC sizes itself against available memory, and a balloon reclaiming underneath it leaves the two chasing pressure the other created. Hence a fixed allocation, with the ARC ceiling stated below.
    balloon = false;
    devices = [
      {
        # The SAS3008 carrying the vault pool, alone in IOMMU group 16. microvm.nix rebinds it to vfio-pci at VM start, so the host needs no vfio-pci.ids.
        bus = "pci";
        path = "0000:01:00.0";
      }
    ];
    # The VT-d aperture cap, carried for the same reason as on the homeassistant guest: the controller's 64-bit BAR would otherwise land above what the IOMMU can map.
    cloud-hypervisor.extraArgs = ["--cpus" "max_phys_bits=39"];
  };

  # The HBA's driver. The pool is not needed for boot, so it stays out of the initrd.
  boot.kernelModules = ["mpt3sas"];

  # Must differ from sparkle's d38a0d1c: ZFS reads it to tell whether another system holds the pool.
  networking.hostId = "4e9d7c21";

  # ARC ceiling, since the allocation above is fixed.
  boot.extraModprobeConfig = "options zfs zfs_arc_max=4294967296";

  # noauto keeps these out of local-fs.target, where they would be attempted before the key is loaded; nfs-server and smbd pull them up through RequiresMountsFor, and x-systemd.requires gives both Requires= and After= on the unlock below.
  # These entries are also what generates zfs-import-vault.service, and with all of them noauto the zfs module hangs it off the mounts.
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

  # Encryption blocks mounting, not importing, so the import runs keyless. Left at its default the generated import service would prompt through systemd-ask-password and hang boot.
  boot.zfs.requestEncryptionCredentials = false;

  # The mirror of the host's forward rules, generated from the same lists so the two cannot disagree.
  networking.firewall.extraInputRules = ''
    ip saddr { ${net.nfsClientsNft} } tcp dport ${toString net.nfsPort} accept
    ip saddr { ${config.host.trustedSubnetsNft} } tcp dport { 139, 445 } accept
    ip saddr { ${discoverySourcesNft} } udp dport { 137, 138 } accept
    ip saddr { ${discoverySourcesNft} } tcp dport 5357 accept
    ip daddr 224.0.0.251 udp dport 5353 accept
    ip daddr 239.255.255.250 udp dport 3702 accept
  '';

  # smartd's alerts, plus avahi's and wsdd's announcements: a multicast response opens a new conntrack tuple, so it takes an accept of its own.
  # The msmtp flow names no destination, since ProtonMail's addresses move, so it keeps the private-space exclusion. The wsdd reply is scoped by destination instead, to the same discovery sources the ingress rules admit, since the reply goes back to whichever of them sent the probe.
  # Only the destination port is runtime state. wsdd binds its unicast socket to 3702 and answers from it (uc_send_socket in the wsdd source), so the flow is scoped by source port.
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

  # SMART on the passed-through array. Only this guest can see these disks, so only it can monitor them.
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

  # The same ProtonMail submission endpoint and relay account sparkle uses, with this guest's own copy of the password.
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

  # The identity the writable export squashes to, so writes are owned by the torrents service whatever uid qbittorrent runs as.
  users.groups.torrents.gid = 3000;
  users.users.torrents = {
    isSystemUser = true;
    uid = 3000;
    group = "torrents";
    description = "Owner of the torrents dataset";
  };

  # NFSv4 only, so the surface is tcp 2049 alone: no rpcbind, statd or mountd to admit, and nfs-utils builds the pseudo-root from these entries.
  # all_squash throughout, because NFS with IP authorisation is AUTH_SYS and the server trusts the uid the client sends; squashing keeps that from becoming a uid-alignment problem across four guests.
  # crossmnt lets the proxy see into the library child. kavita gets that child as its own export, whose separate fsid is what makes no_subtree_check a real boundary.
  services.nfs.server = {
    enable = true;
    exports = ''
      /vault/misc ${net.vmAddress.proxy}(ro,sec=sys,no_subtree_check,crossmnt,all_squash,anonuid=1000,anongid=100)
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

  # Separate from the import so the dependency on the sops secret is stated explicitly.
  # -L keeps keylocation off the pool: imported anywhere else it prompts, which is what leaves recovery possible without this guest or sops.
  systemd.services.vault-unlock = {
    description = "Load the vault pool's encryption key";
    requires = ["zfs-import-vault.service"];
    after = ["zfs-import-vault.service"];
    before = ["shutdown.target"];
    conflicts = ["shutdown.target"];
    # The mounts requiring this are ordered before local-fs.target, which itself precedes sysinit.target and basic.target. Default dependencies would order this after basic.target and close a cycle that systemd resolves by cancelling local-fs.target's job. Nothing here needs sysinit.target: the sops secret is placed by an activation script, which runs before systemd starts.
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
