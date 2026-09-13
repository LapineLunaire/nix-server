{
  config,
  lib,
  pkgs,
  ...
}: {
  options.services.postgresql.passwordFiles = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    description = "Runtime password files keyed by PostgreSQL role name.";
  };

  config.systemd.services.postgresql-passwords = let
    passwords = config.services.postgresql.passwordFiles;
    roles = lib.imap0 (index: name: {
      inherit name;
      id = toString index;
    }) (builtins.attrNames passwords);
    sql = pkgs.writeText "postgresql-passwords.sql" (lib.concatMapStrings ({id, ...}: ''
        \getenv role_${id} PG_ROLE_${id}
        \getenv password_${id} PG_PASSWORD_${id}
        ALTER ROLE :"role_${id}" WITH PASSWORD :'password_${id}';
      '')
      roles);
  in {
    description = "Set PostgreSQL user passwords from sops secrets";
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      # SOPS only restarts active units when credentials change.
      RemainAfterExit = true;
      User = "postgres";
      LoadCredential = map ({
        id,
        name,
      }: "${id}:${passwords.${name}}")
      roles;
    };
    # Let psql quote identifiers and passwords. Keep secret values out of SQL files and argv.
    script =
      lib.concatMapStrings ({
        id,
        name,
      }: ''
        export PG_ROLE_${id}=${lib.escapeShellArg name}
        PG_PASSWORD_${id}=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/${id}")
        export PG_PASSWORD_${id}
      '')
      roles
      + ''
        exec ${config.services.postgresql.package}/bin/psql --no-psqlrc --set ON_ERROR_STOP=1 --single-transaction -f ${sql}
      '';
  };
}
