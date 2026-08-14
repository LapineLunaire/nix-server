# The databases ejabberd runs on: PostgreSQL with its role passwords applied from sops after startup, and Redis for session and cache storage.
{
  config,
  outputs,
  pkgs,
  ...
}: {
  imports = [outputs.nixosModules.postgresql-passwords];

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    ensureDatabases = ["ejabberd"];
    ensureUsers = [
      {
        name = "ejabberd";
        ensureDBOwnership = true;
      }
      {
        name = "carmilla";
        ensureClauses.superuser = true;
      }
    ];
    authentication = ''
      host all all 127.0.0.1/32 scram-sha-256
      host all all ::1/128 scram-sha-256
    '';
  };

  sops.templates."postgresql-passwords.sql" = {
    owner = "postgres";
    content = ''
      ALTER USER ejabberd WITH PASSWORD '${config.sops.placeholder."ejabberd-db-password"}';
      ALTER USER carmilla WITH PASSWORD '${config.sops.placeholder."carmilla-db-password"}';
    '';
  };

  # ejabberd's default_ram_db, on db 1 as set in its own config.
  services.redis.servers."" = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    requirePassFile = config.sops.secrets."redis-password".path;
  };
}
