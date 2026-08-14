# carmilla's home-manager programs: the shell and the terminal tooling.
{
  config,
  pkgs,
  ...
}: {
  home.sessionVariables = {
    PAGER = "nvimpager";
    MANPAGER = "nvimpager";
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.btop = {
    enable = true;
    settings = {
      color_theme = "TTY";
      theme_background = false;
      truecolor = true;
      vim_keys = true;
      update_ms = 1000;
    };
  };

  programs.nixvim = {
    enable = true;
    # Reuse the host's nixpkgs instance for nixvim's packages.
    nixpkgs.pkgs = pkgs;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    opts = {
      number = true;
      relativenumber = true;
      signcolumn = "yes";
      termguicolors = true;
      undofile = true;
      clipboard = "unnamedplus";
    };
  };

  programs.tealdeer = {
    enable = true;
    settings.updates.auto_update = true;
  };

  programs.tmux = {
    enable = true;
    mouse = true;
    keyMode = "vi";
    baseIndex = 1;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    history = {
      path = "${config.xdg.dataHome}/zsh/history";
      share = true;
    };
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = ''
      setopt extendedglob nomatch
      unsetopt beep
      bindkey -v

      PROMPT='%B%F{blue}%m %F{magenta}%~ %F{blue}λ %b%f'
    '';
    shellAliases = {
      pk = "pkill";
      grep = "grep --color=auto";
      egrep = "egrep --color=auto";
      fgrep = "fgrep --color=auto";
      # Use CoW reflinks on supported filesystems (ZFS, btrfs), falling back to a regular copy. --sparse=always avoids writing zero blocks explicitly.
      cp = "cp --reflink=auto --sparse=always";
      sops = "SOPS_AGE_KEY=\"$(doas cat /etc/ssh/ssh_host_ed25519_key | ssh-to-age -private-key)\" sops";
    };
  };
}
