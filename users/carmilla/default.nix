# carmilla: the interactive account on every full host, its OS side and its home-manager wiring. The login password comes from the carmilla-password-hash sops secret, which each host declares.
# home.stateVersion is declared per host alongside system.stateVersion, since it records the nixpkgs release that host was installed from.
{
  config,
  pkgs,
  ...
}: {
  users.users.carmilla = {
    isNormalUser = true;
    uid = 1000;
    description = "Carmilla";
    home = "/home/carmilla";
    shell = pkgs.zsh;
    extraGroups = ["wheel"];
    hashedPasswordFile = config.sops.secrets."carmilla-password-hash".path;
    openssh.authorizedKeys.keys = import ./ssh-keys.nix;
  };

  home-manager.users.carmilla = {
    imports = [
      ./packages.nix
      ./programs.nix
    ];

    home = {
      username = "carmilla";
      homeDirectory = config.users.users.carmilla.home;
    };

    programs.home-manager.enable = true;

    # Activate new and changed systemd user services on switch, without a logout and login cycle.
    systemd.user.startServices = "sd-switch";
  };
}
