{
  config,
  pkgs,
  ...
}: {
  imports = [../../../modules/nixos/postgresql-passwords.nix];

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

  services.postgresql.passwordFiles = {
    ejabberd = config.sops.secrets."ejabberd-db-password".path;
    carmilla = config.sops.secrets."carmilla-db-password".path;
  };

  # ejabberd's default_ram_db, on db 1 as set in its own config.
  services.redis.servers."" = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    requirePassFile = config.sops.secrets."redis-password".path;
  };
}
