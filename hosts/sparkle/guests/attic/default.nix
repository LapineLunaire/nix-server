# The binary cache the CI runner fills and sparkle substitutes from. Reached only through the proxy guest, which terminates TLS for it.
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

  # atticd chunks and compresses on push and answers the proxy, both on the segment, so no egress is declared and the guest reaches nothing off it.

  # atticd reads both from the environment. The database URL carries the password, which is why the config file below declares no url at all.
  sops.templates."atticd.env".content = ''
    ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder."attic-token-rs256-secret-base64"}
    ATTIC_SERVER_DATABASE_URL=postgresql://attic:${config.sops.placeholder."attic-db-password"}@${net.vmAddress.postgres}/attic
  '';

  services.atticd = {
    enable = true;
    environmentFile = config.sops.templates."atticd.env".path;
    settings = {
      listen = "${net.vmAddress.attic}:${toString web.endpoints.attic.port}";
      # The proxy is the only client and sends the vhost name; an empty list would accept any Host.
      allowed-hosts = [web.vhost.attic];
      # Required to end in a slash. Left unset, atticd synthesizes it from the Host header, which the proxy would make wrong.
      api-endpoint = "${web.origin.attic}/";
      # Forced empty so the table carries no url key: attic reads ATTIC_SERVER_DATABASE_URL only as a serde default, so any url here would win and the password would never be used. The module sets a sqlite default that must be displaced.
      database = lib.mkForce {};
      # No quota bounds the store, so retention is what keeps it from growing into /persist.
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "30 days";
      };
    };
  };
}
