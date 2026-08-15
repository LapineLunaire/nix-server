{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."pgadmin-admin-password" = {};
    secrets."pgadmin-oidc-client-secret" = {};
  };
}
