# The attic caches declared in host.binaryCache, added as substituters with the pull token rendered into the netrc nix authenticates with.
# extra-substituters keeps cache.nixos.org in the list.
{
  config,
  lib,
  ...
}: let
  cfg = config.host.binaryCache;
  # netrc keys on host rather than on cache path, so two caches served by one host share an entry.
  machines = lib.unique (map (cache: builtins.head (lib.splitString "/" (lib.removePrefix "https://" cache.url))) cfg.caches);
in
  lib.mkIf (cfg.caches != []) {
    assertions = [
      {
        assertion = cfg.tokenSecret != null;
        message = "host.binaryCache.caches is set on ${config.networking.hostName} with no tokenSecret; the caches are private and nix cannot authenticate without one.";
      }
    ];

    sops.secrets.${cfg.tokenSecret} = {};

    sops.templates."nix-netrc".content =
      lib.concatMapStrings (machine: ''
        machine ${machine} password ${config.sops.placeholder.${cfg.tokenSecret}}
      '')
      machines;

    nix.settings = {
      extra-substituters = map (cache: cache.url) cfg.caches;
      extra-trusted-public-keys = map (cache: cache.publicKey) cfg.caches;
      netrc-file = config.sops.templates."nix-netrc".path;
    };
  }
