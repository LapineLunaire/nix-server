{
  config,
  lib,
  outputs,
  pkgs,
  ...
}: let
  inherit (config.host) smtp;
  dmz = import ./dmz-net.nix;
  trustedSubnets = import ./trusted-subnets.nix;
in {
  imports = [
    outputs.nixosModules.host-base
    outputs.nixosModules.zfs
    # Keeps sshd unreachable from the DMZ, where the guests are peers but not trusted, and from the management network and the sparxie tunnel.
    outputs.nixosModules.trusted-ssh-ingress
    ./hardware-configuration.nix
    ./sops.nix
    ./services
    ./dmz-bridge.nix
  ];

  # Client subnets trusted to reach sparkle's own sshd, and through the bridge forward chain the fleet's admin surfaces. From trusted-subnets.nix, shared with the proxy, vault, and forgejo guests so the lists cannot drift.
  host.trustedSubnets = trustedSubnets.all;

  # The ProtonMail submission endpoint and the noreply relay account, used by msmtp for smartd alerts. The password secret lives in this host's sops.
  host.smtp = {
    host = "smtp.protonmail.ch";
    port = "587";
    user = "noreply@lunaire.eu";
  };

  host.flakePath = "/persist/nix-config";

  networking = {
    hostName = "sparkle";
    hostId = "d38a0d1c";
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
  programs.msmtp = {
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
    # Rebuilt with X86_NATIVE_CPU, which targets the CPU the kernel is compiled on. This kernel is specific to sparkle's hardware, and sparkle builds it itself.
    kernelPackages = pkgs.linuxPackages_6_18.extend (
      _: super: {
        kernel = super.kernel.override {
          structuredExtraConfig = {
            X86_NATIVE_CPU = lib.kernel.yes;
          };
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
