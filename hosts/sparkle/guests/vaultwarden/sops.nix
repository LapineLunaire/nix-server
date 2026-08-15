{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."vaultwarden-db-password" = {};
    secrets."vaultwarden-admin-token" = {};
    secrets."vaultwarden-smtp-password" = {};
  };
}
