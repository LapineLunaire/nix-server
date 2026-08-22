# Base NixOS for full hosts: boot loader, escalation rules, zram, locale, console, and the firewall and networkd defaults, on top of the option namespace, nix settings, hardening, persisted state, packages, services, and temp dir mounts.
{
  lib,
  outputs,
  pkgs,
  ...
}: {
  imports = [
    outputs.modules.host
    outputs.modules.nix-settings
    outputs.nixosModules.security
    ./packages.nix
    ./persistence.nix
    ./services.nix
    ./tmp-dirs.nix
  ];

  boot = {
    initrd.systemd.enable = true;
    loader = {
      systemd-boot = {
        enable = lib.mkDefault true;
        # Editing the kernel command line at the boot menu allows root access via init=/bin/sh.
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };
    # High swappiness suits zram: compressed pages stay in RAM, so a swap-out costs compression time.
    kernel.sysctl."vm.swappiness" = 100;
  };

  # wheel escalates with doas, and persist caches the authentication for a period after a successful prompt.
  security.doas = {
    enable = true;
    extraRules = [
      {
        groups = ["wheel"];
        persist = true;
      }
    ];
  };
  # doas-sudo-shim installs one binary, named sudo, that calls doas. modules/nixos/security.nix disables the real sudo.
  environment.systemPackages = [pkgs.doas-sudo-shim];

  security.polkit.enable = true;

  # Let wheel group members reboot and power off without a password prompt.
  environment.etc."polkit-1/rules.d/50-wheel-power.rules".text = ''
    polkit.addRule(function (action, subject) {
      if (
        subject.isInGroup("wheel") &&
        [
          "org.freedesktop.login1.reboot",
          "org.freedesktop.login1.reboot-multiple-sessions",
          "org.freedesktop.login1.power-off",
          "org.freedesktop.login1.power-off-multiple-sessions",
        ].indexOf(action.id) !== -1
      ) {
        return polkit.Result.YES;
      }
    });
  '';

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 30;
    priority = 100;
  };

  time.timeZone = lib.mkDefault "UTC";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "C.UTF-8"; # ISO 8601 time format
      LC_MONETARY = "nl_NL.UTF-8";
      LC_MEASUREMENT = "nl_NL.UTF-8";
      LC_PAPER = "nl_NL.UTF-8";
    };
  };

  console = {
    font = "Lat2-Terminus16";
    earlySetup = true;
  };

  networking.firewall.enable = true;
  networking.nftables.enable = true;

  systemd.network.enable = lib.mkDefault true;
  # Suppresses the catch-all networkd unit that would otherwise enable DHCP on every interface without a manually configured address.
  networking.useDHCP = false;
}
