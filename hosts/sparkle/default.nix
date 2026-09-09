{
  config,
  outputs,
  pkgs,
  ...
}: let
  dmz = import ./dmz-net.nix;
in {
  imports = [
    outputs.nixosModules.host-base
    outputs.nixosModules.binary-cache
    outputs.nixosModules.secure-boot
    outputs.nixosModules.zfs
    # Keeps sshd unreachable from the DMZ, where the guests are peers but not trusted, and from the management network and the sparxie tunnel.
    outputs.nixosModules.trusted-ssh-ingress
    ./hardware-configuration.nix
    ./sops.nix
    ./services
    ./dmz-bridge.nix
    ./auto-update.nix
    (outputs.lib.mkMicrovmHost {
      registry = import ./guest-registry.nix;
      inherit (dmz) bridge;
    })
  ];

  # Client subnets trusted to reach sparkle's own sshd, and through the bridge forward chain the guests' admin surfaces. From trusted-subnets.nix, shared with the proxy, vault, and forgejo guests so the lists cannot drift.
  host.trustedSubnets = (import ./trusted-subnets.nix).all;

  # The ProtonMail submission endpoint and the noreply relay account, used by msmtp for smartd alerts. The password secret lives in this host's sops.
  host.smtp = {
    host = "smtp.protonmail.ch";
    port = "587";
    user = "noreply@lunaire.eu";
  };

  host.flakePath = "/persist/nix-config";

  # The attic guest this host runs. The key is read off `attic cache info server`; a literal here for the same reason consoleKey is one in flake.nix.
  host.binaryCache = {
    caches = [
      {
        url = "https://cache.lunaire.moe/server";
        publicKey = "server:oFkIrocLJr2oRVgeOqJ1TUUPwTYLWKm0Lpg9aRKU5zU=";
      }
    ];
    tokenSecret = "attic-pull-token";
  };

  # Raptor Lake-S. gcc 15.2, the compiler that builds this kernel, resolves -march=native to alderlake on this CPU and enables an identical target flag set for both names.
  host.cpu.march = "alderlake";

  networking = let
    net = import ./guest-net.nix;
  in {
    hostName = "sparkle";
    hostId = "d38a0d1c";
    # Nothing on the host binds 53, so resolved is left at the networkd default and takes the dns guest as its upstream.
    nameservers = [net.vmAddress.dns];
  };

  # Interface names are assigned by sops-rendered .link files (see sops.nix). sfp0 is the primary uplink and is enslaved to the dmz0 bridge, which carries the address (see dmz-bridge.nix). sfp1 and ipmi0 are left unmanaged.
  systemd.network.networks = {
    "10-sfp0" = {
      matchConfig.Name = "sfp0";
      networkConfig = {
        DHCP = "no";
        Bridge = dmz.bridge;
      };
    };
    "10-sfp1" = {
      matchConfig.Name = "sfp1";
      linkConfig.Unmanaged = true;
    };
    "99-ipmi0" = {
      matchConfig.Name = "ipmi0";
      # Leave the IPMI interface alone; its static config lives on the BMC.
      linkConfig.Unmanaged = true;
    };
  };

  # System SMTP relay so automated daemons, currently smartd, can send alerts.
  programs.msmtp = let
    inherit (config.host) smtp;
  in {
    enable = true;
    setSendmail = true;
    accounts.default = {
      inherit (smtp) host port user;
      auth = true;
      tls = true;
      from = smtp.user;
      passwordeval = "cat ${config.sops.secrets."smartd-smtp-password".path}";
    };
  };

  # Keep the host off devices passed through to guests: the Zigbee stick's USB controller goes to the homeassistant guest, the SAS HBA whole to the vault guest. microvm.nix rebinds either at VM start, and blacklisting leaves the HBA unclaimed from boot onward.
  boot.blacklistedKernelModules = ["cp210x" "mpt3sas"];

  boot = {
    # Compiled for the microarchitecture host.cpu.march names rather than for whatever machine ran the build, so the derivation records the target and the result substitutes.
    # One flag per list element, none with an embedded space: the generic kernel builder splices $makeFlags
    # into `make` unquoted, so a value like "-march=x -mtune=x" in one element breaks apart into a second
    # word make reads as an unknown flag.
    # arch/x86/Makefile always appends "-march=x86-64 -mtune=generic" after KCFLAGS when CONFIG_X86_NATIVE_CPU
    # is off, so KCFLAGS alone wins the ISA but leaves -mtune=generic in place; CFLAGS_KERNEL/CFLAGS_MODULE
    # set -mtune directly, per kernel and module objects. KRUSTFLAGS covers the Rust objects, which KCFLAGS
    # does not touch at all.
    kernelPackages = let
      inherit (config.host.cpu) march;
    in
      if march == null
      then pkgs.linuxPackages_6_18
      else
        pkgs.linuxPackages_6_18.extend (
          _: super: {
            kernel = super.kernel.override {
              extraMakeFlags = [
                "KCFLAGS=-march=${march}"
                "CFLAGS_KERNEL=-mtune=${march}"
                "CFLAGS_MODULE=-mtune=${march}"
                "KRUSTFLAGS=-Ctarget-cpu=${march}"
              ];
            };
          }
        );
    kernelParams = [
      "intel_pstate=active"
      "intel_iommu=on"
      "iommu=pt"
    ];
    # Explicit zfs major version pin, upgraded deliberately in lockstep with the kernel pin above.
    zfs.package = pkgs.zfs_2_4;
  };

  # With intel_pstate active, powersave leaves frequency scaling to the HWP firmware.
  powerManagement.cpuFreqGovernor = "powersave";

  system.stateVersion = "26.05";
  home-manager.users.carmilla.home.stateVersion = "26.05";
}
