{
  config,
  guestConfigurations,
  pkgs,
  ...
}: let
  dmz = import ./dmz-net.nix;
in {
  imports = [
    ../../modules/nixos/host-base
    ../../modules/nixos/secure-boot.nix
    ../../modules/nixos/zfs.nix
    # Only trusted client networks may reach the host's SSH service.
    ../../modules/nixos/trusted-ssh-ingress.nix
    ./binary-cache.nix
    ./hardware-configuration.nix
    ./sops.nix
    ./services
    ./dmz-bridge.nix
    ./auto-update.nix
    (import ../../modules/nixos/microvm/host.nix {
      inherit guestConfigurations;
      registry = import ./guest-registry.nix;
      inherit (dmz) bridge;
    })
  ];

  host.trustedSubnets = (import ./trusted-subnets.nix).all;

  host.smtp = {
    host = "smtp.protonmail.ch";
    port = "587";
    user = "noreply@lunaire.eu";
  };

  host.flakePath = "/persist/nix-config";

  networking = let
    net = import ./guest-net.nix;
  in {
    hostName = "sparkle";
    hostId = "d38a0d1c";
    # Use the DNS guest as systemd-resolved's upstream.
    nameservers = [net.vmAddress.dns];
  };

  # sops.nix assigns these names. Only sfp0 joins the DMZ bridge.
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
      # The BMC manages its own network configuration.
      linkConfig.Unmanaged = true;
    };
  };

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

  # Leave the Zigbee controller and SAS HBA for their guests.
  boot.blacklistedKernelModules = ["cp210x" "mpt3sas"];

  boot = {
    # Keep each make flag separate. Set C and Rust targets explicitly for reproducible builds.
    # CFLAGS_KERNEL and CFLAGS_MODULE override the kernel's generic tuning flags.
    kernelPackages = let
      march = "alderlake";
    in
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
    # Update ZFS and the kernel together.
    zfs.package = pkgs.zfs_2_4;
  };

  # HWP firmware controls frequency scaling in powersave mode.
  powerManagement.cpuFreqGovernor = "powersave";

  system.stateVersion = "26.05";
  home-manager.users.carmilla.home.stateVersion = "26.05";
}
