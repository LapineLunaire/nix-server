{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."authelia-jwt-secret".owner = "authelia-main";
    secrets."authelia-session-secret".owner = "authelia-main";
    secrets."authelia-storage-encryption-key".owner = "authelia-main";
    secrets."authelia-oidc-hmac-secret".owner = "authelia-main";
    secrets."authelia-oidc-issuer-key".owner = "authelia-main";
    secrets."authelia-users".owner = "authelia-main";
    secrets."authelia-db-password" = {};
    secrets."authelia-smtp-password" = {};
    secrets."authelia-forgejo-client-secret-hash" = {};
    secrets."redis-authelia-password".owner = "redis-authelia";
    secrets."pgadmin-oidc-client-secret-hash" = {};
    templates."authelia.yaml".owner = "authelia-main";
  };
}
