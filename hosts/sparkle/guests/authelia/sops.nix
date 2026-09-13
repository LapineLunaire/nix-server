{lib, ...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets =
      lib.genAttrs [
        "authelia-jwt-secret"
        "authelia-session-secret"
        "authelia-storage-encryption-key"
        "authelia-oidc-hmac-secret"
        "authelia-oidc-issuer-key"
        "authelia-users"
        "authelia-db-password"
        "authelia-smtp-password"
      ] (_: {
        owner = "authelia-main";
        restartUnits = ["authelia-main.service"];
      })
      // {
        "authelia-forgejo-client-secret-hash" = {};
        "pgadmin-oidc-client-secret-hash" = {};
        "redis-authelia-password" = {
          owner = "redis-authelia";
          group = "authelia-main";
          mode = "0440";
          restartUnits = ["redis-authelia.service" "authelia-main.service"];
        };
      };
    templates."authelia.yaml" = {
      owner = "authelia-main";
      restartUnits = ["authelia-main.service"];
    };
  };
}
