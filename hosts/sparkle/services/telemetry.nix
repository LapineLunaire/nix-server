{
  config,
  pkgs,
  ...
}: let
  dmz = import ../dmz-net.nix;
  net = import ../guest-net.nix;
in {
  programs.msmtp = let
    inherit (config.host) smtp;
  in {
    enable = true;
    setSendmail = true;
    accounts.default = {
      inherit (smtp) host port user;
      auth = true;
      tls = true;
      from = smtp.user;
      passwordeval = "cat ${config.sops.secrets."smartd-smtp-password".path}";
    };
  };

  services.smartd = {
    enable = true;
    # Alerts leave through the host's msmtp relay above.
    notifications.mail = {
      enable = true;
      sender = config.host.smtp.user;
      recipient = "carmilla@lunaire.eu";
    };
  };
  # smartd depends on smartmontools but does not put smartctl on PATH.
  environment.systemPackages = [pkgs.smartmontools];

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = dmz.hostAddress;
    port = net.nodeExporterPort;
  };

  networking.firewall.extraInputRules = ''
    ip saddr ${net.vmAddress.monitoring} tcp dport ${toString net.nodeExporterPort} accept
    # Uptime Kuma checks the host's SSH service through the input firewall.
    ip saddr ${net.vmAddress.uptime-kuma} tcp dport 22 accept
  '';
}
