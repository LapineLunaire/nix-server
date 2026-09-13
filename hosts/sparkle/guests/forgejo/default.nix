{
  config,
  net,
  trustedSubnets,
  web,
  ...
}: {
  imports = [
    # Git-over-SSH on port 22 uses the system sshd; open it to git clients on the trusted subnets.
    ../../../../modules/nixos/trusted-ssh-ingress.nix
    ./sops.nix
  ];

  host.trustedSubnets = trustedSubnets.all;

  host.smtp = {
    host = "smtp.protonmail.ch";
    port = "587";
    user = "noreply@lunaire.eu";
  };

  microvm = {
    vcpu = 2;
    mem = 1536;
    initialBalloonMem = 256;
  };

  # Webhook targets and push mirrors are per-repository settings, and a mirror can use ssh or the git protocol.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  sops.templates."forgejo.env".content = ''
    FORGEJO__mailer__PASSWD=${config.sops.placeholder."forgejo-smtp-password"}
  '';
  systemd.services.forgejo.serviceConfig.EnvironmentFile = config.sops.templates."forgejo.env".path;

  services.forgejo = let
    inherit (config.host) smtp;
  in {
    enable = true;
    database = {
      type = "postgres";
      host = net.vmAddress.postgres;
      passwordFile = config.sops.secrets."forgejo-db-password".path;
      createDatabase = false;
    };
    settings = {
      security = {
        REVERSE_PROXY_LIMIT = 1;
        REVERSE_PROXY_TRUSTED_PROXIES = net.vmAddress.proxy;
      };
      server = {
        DOMAIN = web.vhost.forgejo;
        ROOT_URL = "${web.origin.forgejo}/";
        HTTP_PORT = web.endpoints.forgejo.port;
        SSH_DOMAIN = "git-ssh.${web.domain}";
      };
      mailer = {
        ENABLED = true;
        SMTP_ADDR = smtp.host;
        SMTP_PORT = smtp.port;
        FROM = "Forgejo <${smtp.user}>";
        USER = smtp.user;
      };
      service = {
        DISABLE_REGISTRATION = true;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        SHOW_REGISTRATION_BUTTON = false;
      };
      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "github";
      };
    };
  };
}
