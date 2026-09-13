{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../host.nix
    ../../nix-settings.nix
    ../security.nix
    ./persistence.nix
  ];

  boot = {
    initrd.systemd.enable = true;
    loader = {
      systemd-boot = {
        enable = lib.mkDefault true;
        # Prevent boot-menu edits such as init=/bin/sh.
        editor = false;
      };
      efi.canTouchEfiVariables = true;
    };
    # Prefer compression in zram before reclaiming the file cache.
    kernel.sysctl."vm.swappiness" = 100;
  };

  security.doas = {
    enable = true;
    extraRules = [
      {
        groups = ["wheel"];
        persist = true;
      }
    ];
  };
  # Use doas for tools that invoke sudo.
  environment.systemPackages = [pkgs.ghostty.terminfo pkgs.doas-sudo-shim];

  security.polkit.enable = true;

  # Allow wheel to reboot or shut down remotely.
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
      LC_TIME = "C.UTF-8";
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

  programs.zsh.enable = true;

  # Also provide an editor for root shells.
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
  };

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep 3";
      dates = "daily";
    };
    flake = config.host.flakePath;
  };

  services.dbus.implementation = "broker";
  services.fstrim.enable = true;
  services.fwupd.enable = true;

  services.chrony = {
    enable = true;
    enableNTS = true;
    servers = ["time.cloudflare.com"];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AuthenticationMethods = "publickey";
    };
    # Also used as the SOPS decryption identity.
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  systemd.network.enable = lib.mkDefault true;
  # Avoid networkd's catch-all DHCP configuration on unconfigured interfaces.
  networking.useDHCP = false;
}
