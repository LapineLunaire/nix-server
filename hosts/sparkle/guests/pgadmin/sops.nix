{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."pgadmin-admin-password".restartUnits = ["pgadmin.service"];
    secrets."pgadmin-oidc-client-secret".restartUnits = ["pgadmin.service"];
  };
}
