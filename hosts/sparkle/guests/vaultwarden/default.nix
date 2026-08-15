{
  config,
  net,
  web,
  ...
}: let
  inherit (config.host) smtp;
in {
  imports = [./sops.nix];

  # The ProtonMail SMTP submission endpoint and the noreply relay account for vaultwarden's outgoing mail; the password secret lives in this VM's sops.
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

  # SMTP is declared, but icon fetching reaches any site a stored entry names.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  sops.templates."vaultwarden.env".content = ''
    ADMIN_TOKEN=${config.sops.placeholder."vaultwarden-admin-token"}
    DATABASE_URL=postgresql://vaultwarden:${config.sops.placeholder."vaultwarden-db-password"}@${net.vmAddress.postgres}/vaultwarden
    SMTP_HOST=${smtp.host}
    SMTP_PORT=${smtp.port}
    SMTP_SECURITY=starttls
    SMTP_FROM=${smtp.user}
    SMTP_FROM_NAME=Vaultwarden
    SMTP_USERNAME=${smtp.user}
    SMTP_PASSWORD=${config.sops.placeholder."vaultwarden-smtp-password"}
  '';

  services.vaultwarden = {
    enable = true;
    dbBackend = "postgresql";
    environmentFile = config.sops.templates."vaultwarden.env".path;
    config = {
      DOMAIN = web.origin.vaultwarden;
      ROCKET_ADDRESS = net.vmAddress.vaultwarden;
      ROCKET_PORT = web.endpoints.vaultwarden.port;
      SIGNUPS_ALLOWED = false;
    };
  };
}
