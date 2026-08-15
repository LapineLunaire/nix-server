{
  config,
  net,
  web,
  outputs,
  ...
}: let
in {
  imports = [outputs.nixosModules.microvm-docker-common ./sops.nix];

  microvm = {
    vcpu = 1;
    mem = 1536;
    initialBalloonMem = 256;
    volumes = [
      {
        image = "/persist/vms/pgadmin/volumes/docker.img";
        mountPoint = "/var/lib/docker";
        size = 5120;
        fsType = "xfs";
      }
    ];
  };

  # Container image pulls.
  microvmGuest.egress = [
    {
      proto = "tcp";
      ports = [443];
    }
  ];

  sops.templates."pgadmin.env".content = ''
    PGADMIN_DEFAULT_PASSWORD=${config.sops.placeholder."pgadmin-admin-password"}
    PGADMIN_CONFIG_AUTHENTICATION_SOURCES=['oauth2']
    PGADMIN_CONFIG_OAUTH2_AUTO_CREATE_USER=True
    PGADMIN_CONFIG_OAUTH2_CONFIG=[{'OAUTH2_NAME': 'authelia', 'OAUTH2_DISPLAY_NAME': 'Lunaire SSO', 'OAUTH2_CLIENT_ID': 'pgadmin', 'OAUTH2_CLIENT_SECRET': '${config.sops.placeholder."pgadmin-oidc-client-secret"}', 'OAUTH2_SERVER_METADATA_URL': '${web.origin.authelia}/.well-known/openid-configuration', 'OAUTH2_USERINFO_ENDPOINT': '${web.origin.authelia}/api/oidc/userinfo', 'OAUTH2_SCOPE': 'openid email profile', 'OAUTH2_USERNAME_CLAIM': 'preferred_username'}]
  '';

  virtualisation.oci-containers.containers.pgadmin = {
    image = "dpage/pgadmin4@sha256:2f4ce946ddf8360680d7eff4eaba1d91859eb6b4003e6623bad5c63a322c2f4d";
    autoStart = true;
    environment = {
      PGADMIN_DEFAULT_EMAIL = "carmilla@lunaire.eu";
      PGADMIN_LISTEN_ADDRESS = net.vmAddress.pgadmin;
      PGADMIN_LISTEN_PORT = toString web.endpoints.pgadmin.port;
    };
    environmentFiles = [config.sops.templates."pgadmin.env".path];
    volumes = ["/persist/var/lib/pgadmin:/var/lib/pgadmin"];
    # Host networking so pgadmin binds the VM address directly and its ingress is gated by the guest input firewall; a published port is DNAT'd inside the guest and bypasses that chain entirely.
    extraOptions = ["--network=host"];
  };
}
