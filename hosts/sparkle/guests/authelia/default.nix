{
  config,
  net,
  web,
  ...
}: let
  inherit (config.host) smtp;
in {
  imports = [./sops.nix];

  # The ProtonMail SMTP submission endpoint and the noreply relay account for authelia's outgoing mail; the password secret lives in this VM's sops.
  host.smtp = {
    host = "smtp.protonmail.ch";
    port = "587";
    user = "noreply@lunaire.eu";
  };

  microvm = {
    vcpu = 1;
    mem = 768;
    initialBalloonMem = 256;
  };

  # SMTP submission, its only outbound.
  microvmGuest.egress = [
    {
      proto = "tcp";
      ports = [587];
    }
  ];

  sops.templates."authelia.yaml".content = ''
    storage:
      postgres:
        password: '${config.sops.placeholder."authelia-db-password"}'
    session:
      redis:
        password: '${config.sops.placeholder."redis-authelia-password"}'
    notifier:
      smtp:
        password: '${config.sops.placeholder."authelia-smtp-password"}'
    identity_providers:
      oidc:
        clients:
          - client_id: pgadmin
            client_name: pgAdmin
            client_secret: '${config.sops.placeholder."pgadmin-oidc-client-secret-hash"}'
            public: false
            authorization_policy: two_factor
            redirect_uris:
              - ${web.origin.pgadmin}/oauth2/authorize
            scopes:
              - openid
              - profile
              - email
            userinfo_signed_response_alg: none
            grant_types:
              - authorization_code
            response_types:
              - code
  '';

  services.redis.servers.authelia = {
    enable = true;
    bind = "127.0.0.1";
    port = 6380;
    requirePassFile = config.sops.secrets."redis-authelia-password".path;
  };

  services.authelia.instances.main = {
    enable = true;
    settingsFiles = [config.sops.templates."authelia.yaml".path];
    secrets = {
      jwtSecretFile = config.sops.secrets."authelia-jwt-secret".path;
      sessionSecretFile = config.sops.secrets."authelia-session-secret".path;
      storageEncryptionKeyFile = config.sops.secrets."authelia-storage-encryption-key".path;
      oidcHmacSecretFile = config.sops.secrets."authelia-oidc-hmac-secret".path;
      oidcIssuerPrivateKeyFile = config.sops.secrets."authelia-oidc-issuer-key".path;
    };
    settings = {
      theme = "dark";
      log.level = "info";
      server.address = "tcp://${net.vmAddress.authelia}:${toString web.endpoints.authelia.port}/";
      session = {
        redis = {
          host = "127.0.0.1";
          port = 6380;
        };
        cookies = [
          {
            domain = web.domain;
            authelia_url = web.origin.authelia;
          }
        ];
      };
      storage.postgres = {
        address = "tcp://${net.vmAddress.postgres}:${toString net.postgresPort}";
        database = "authelia";
        username = "authelia";
      };
      authentication_backend.file.path = config.sops.secrets."authelia-users".path;
      webauthn = {
        disable = false;
        display_name = "Lunaire Auth";
        attestation_conveyance_preference = "indirect";
        selection_criteria.user_verification = "preferred";
        timeout = "60s";
      };
      access_control.default_policy = "two_factor";
      notifier.smtp = {
        address = "smtp://${smtp.host}:${smtp.port}";
        username = smtp.user;
        sender = "Authelia <${smtp.user}>";
      };
    };
  };
}
