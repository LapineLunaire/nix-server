# Applies the sops-templated postgresql-passwords.sql after postgres starts. ensureUsers only issues ALTER ROLE with the clauses it is given, so roles are created without passwords and pg_hba would reject them over TCP. The importing host defines the template's ALTER USER content.
{config, ...}: {
  systemd.services.postgresql-passwords = {
    description = "Set PostgreSQL user passwords from sops secrets";
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStart = "${config.services.postgresql.package}/bin/psql -f ${config.sops.templates."postgresql-passwords.sql".path}";
    };
  };
}
