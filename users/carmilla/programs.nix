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
    nix-direnv.enable = true;
  };

  programs.fzf.enable = true;

  # Behaviour only: this account authors no commits here, so it carries no identity or signing key.
  programs.git = {
    enable = true;
    settings = {
      core = {
        editor = "nvim";
        pager = "nvimpager";
      };
      pull.rebase = true;
      init.defaultBranch = "main";
      color.ui = "auto";
      push.autoSetupRemote = true;
      rerere.enabled = true;
      diff.algorithm = "histogram";
      merge.conflictstyle = "zdiff3"; # zdiff3 includes the merge base in conflict markers
      branch.sort = "-committerdate";
    };
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

    colorschemes.gruvbox = {
      enable = true;
      settings.contrast = "hard";
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

  programs.zoxide.enable = true;

  programs.zsh = {
    enable = true;
    history.path = "${config.xdg.dataHome}/zsh/history";
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
