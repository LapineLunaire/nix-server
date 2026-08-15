{
  config,
  net,
  lib,
  outputs,
  pkgs,
  ...
}: let
in {
  imports = [outputs.nixosModules.postgresql-passwords ./sops.nix];

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
    # The databases, roles and pg_hba lines below grow one entry per client guest.
    ensureDatabases = ["authelia"];
    ensureUsers = [
      {
        name = "authelia";
        ensureDBOwnership = true;
      }
      {
        name = "carmilla";
        ensureClauses.superuser = true;
      }
    ];
    authentication = ''
      local all             postgres                        peer
      host  authelia        authelia    ${net.vmAddress.authelia}/32 scram-sha-256
      host  all             carmilla    ${net.vmAddress.pgadmin}/32 scram-sha-256
    '';
  };

  sops.templates."postgresql-passwords.sql".content = ''
    ALTER USER authelia    WITH PASSWORD '${config.sops.placeholder."authelia-db-password"}';
    ALTER USER carmilla    WITH PASSWORD '${config.sops.placeholder."carmilla-db-password"}';
  '';

  networking.firewall.extraInputRules = ''
    ip saddr { ${net.postgresClientsNft} } tcp dport ${toString net.postgresPort} accept
  '';
}
