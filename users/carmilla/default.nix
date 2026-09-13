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

    systemd.user.startServices = "sd-switch";
  };
}
