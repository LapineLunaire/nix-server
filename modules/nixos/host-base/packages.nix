# System-wide programs for full hosts: the login shell, an editor for root shells, nh, and the ghostty terminfo.
{
  config,
  pkgs,
  ...
}: {
  programs.zsh.enable = true;

  # System-wide neovim so root shells have an editor. The user's configured neovim comes from home-manager.
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

  # terminfo so SSH sessions from a Ghostty terminal render correctly.
  environment.systemPackages = [pkgs.ghostty.terminfo];
}
