{config, ...}: {
  sops.secrets."attic-pull-token" = {};
  sops.templates."nix-netrc" = {
    mode = "0400";
    content = ''
      machine cache.lunaire.moe password ${config.sops.placeholder."attic-pull-token"}
    '';
  };

  nix.settings = {
    extra-substituters = ["https://cache.lunaire.moe/server?priority=10"];
    extra-trusted-public-keys = ["server:oFkIrocLJr2oRVgeOqJ1TUUPwTYLWKm0Lpg9aRKU5zU="];
    netrc-file = config.sops.templates."nix-netrc".path;
  };
}
