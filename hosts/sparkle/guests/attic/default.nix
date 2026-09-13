{
  config,
  lib,
  net,
  web,
  ...
}: {
  imports = [./sops.nix];

  microvm = {
    vcpu = 4;
    mem = 2048;
    initialBalloonMem = 512;
  };

  # Read the database URL and signing key from the runtime environment.
  sops.templates."atticd.env" = {
    restartUnits = ["atticd.service"];
    content = ''
      ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder."attic-token-rs256-secret-base64"}
      ATTIC_SERVER_DATABASE_URL=postgresql://attic:${config.sops.placeholder."attic-db-password"}@${net.vmAddress.postgres}/attic
    '';
  };

  services.atticd = {
    enable = true;
    environmentFile = config.sops.templates."atticd.env".path;
    settings = {
      listen = "${net.vmAddress.attic}:${toString web.endpoints.attic.port}";
      allowed-hosts = [web.vhost.attic];
      # Attic requires a trailing slash.
      api-endpoint = "${web.origin.attic}/";
      # Remove the module's SQLite URL so ATTIC_SERVER_DATABASE_URL takes effect.
      database = lib.mkForce {};
      # Bound storage growth with retention.
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "30 days";
      };
    };
  };
}
