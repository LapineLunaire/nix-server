{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."authelia-db-password" = {};
    secrets."forgejo-db-password" = {};
    secrets."vaultwarden-db-password" = {};
    secrets."carmilla-db-password" = {};
    templates."postgresql-passwords.sql".owner = "postgres";
  };
}
