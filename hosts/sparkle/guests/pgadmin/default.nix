{
  config,
  lib,
  net,
  pkgs,
  web,
  ...
}: {
  imports = [./sops.nix];

  microvm = {
    vcpu = 1;
    mem = 1024;
    initialBalloonMem = 256;
  };

  services.pgadmin = {
    enable = true;
    port = web.endpoints.pgadmin.port;
    initialEmail = "carmilla@lunaire.eu";
    initialPasswordFile = config.sops.secrets."pgadmin-admin-password".path;
    settings = {
      DEFAULT_SERVER = net.vmAddress.pgadmin;
      AUTHENTICATION_SOURCES = ["oauth2"];
      OAUTH2_AUTO_CREATE_USER = true;
      OAUTH2_CONFIG = [
        {
          OAUTH2_NAME = "authelia";
          OAUTH2_DISPLAY_NAME = "Lunaire SSO";
          OAUTH2_CLIENT_ID = "pgadmin";
          OAUTH2_SERVER_METADATA_URL = "${web.origin.authelia}/.well-known/openid-configuration";
          OAUTH2_USERINFO_ENDPOINT = "${web.origin.authelia}/api/oidc/userinfo";
          OAUTH2_SCOPE = "openid email profile";
          OAUTH2_USERNAME_CLAIM = "preferred_username";
        }
      ];
    };
  };

  # Read the secret at runtime; the generated Nix configuration contains no secret value.
  environment.etc."pgadmin/config_system.py".text = lib.mkAfter ''
    import os
    with open(os.path.join(os.environ['CREDENTIALS_DIRECTORY'], 'oidc_client_secret')) as secret:
        OAUTH2_CONFIG[0]['OAUTH2_CLIENT_SECRET'] = secret.read().strip()
  '';

  # Match the remote PostgreSQL server for pg_dump/pg_restore on the service PATH.
  services.postgresql.package = pkgs.postgresql_18;

  systemd.services.pgadmin.serviceConfig.LoadCredential = [
    "oidc_client_secret:${config.sops.secrets."pgadmin-oidc-client-secret".path}"
  ];
}
