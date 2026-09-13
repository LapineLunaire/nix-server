{
  config,
  net,
  lib,
  pkgs,
  ...
}: {
  imports = [../../../../modules/nixos/postgresql-passwords.nix ./sops.nix];

  microvm = {
    vcpu = 2;
    mem = 3072;
    initialBalloonMem = 1024;
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    settings = {
      listen_addresses = lib.mkForce "127.0.0.1,${net.vmAddress.postgres}";
      port = net.postgresPort;
      shared_buffers = "512MB";
      effective_cache_size = "1536MB";
      max_connections = 50;
    };
    ensureDatabases = ["attic" "authelia" "forgejo" "vaultwarden"];
    ensureUsers = [
      {
        name = "attic";
        ensureDBOwnership = true;
      }
      {
        name = "authelia";
        ensureDBOwnership = true;
      }
      {
        name = "forgejo";
        ensureDBOwnership = true;
      }
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
      {
        name = "carmilla";
        ensureClauses.superuser = true;
      }
    ];
    authentication = ''
      local all             postgres                        peer
      host  attic           attic       ${net.vmAddress.attic}/32 scram-sha-256
      host  authelia        authelia    ${net.vmAddress.authelia}/32 scram-sha-256
      host  forgejo         forgejo     ${net.vmAddress.forgejo}/32 scram-sha-256
      host  vaultwarden     vaultwarden ${net.vmAddress.vaultwarden}/32 scram-sha-256
      host  all             carmilla    ${net.vmAddress.pgadmin}/32 scram-sha-256
    '';
  };

  services.postgresql.passwordFiles = {
    attic = config.sops.secrets."attic-db-password".path;
    authelia = config.sops.secrets."authelia-db-password".path;
    forgejo = config.sops.secrets."forgejo-db-password".path;
    vaultwarden = config.sops.secrets."vaultwarden-db-password".path;
    carmilla = config.sops.secrets."carmilla-db-password".path;
  };

  networking.firewall.extraInputRules = ''
    ip saddr { ${net.postgresClientsNft} } tcp dport ${toString net.postgresPort} accept
  '';
}
