# sparkle's own telemetry. The monitoring stack itself lives in the monitoring guest.
{
  config,
  pkgs,
  ...
}: {
  services.smartd = {
    enable = true;
    # Alerts leave through the host's msmtp relay, configured in default.nix.
    notifications.mail = {
      enable = true;
      sender = config.host.smtp.user;
      recipient = "carmilla@lunaire.eu";
    };
  };
  # smartd depends on smartmontools but does not put smartctl on PATH.
  environment.systemPackages = [pkgs.smartmontools];

  imports = [
    (let
      dmz = import ../dmz-net.nix;
      net = import ../guest-net.nix;
    in {
      # node_exporter on sparkle, bound to the dmz0 address so the monitoring guest can scrape it.
      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = dmz.hostAddress;
        port = net.nodeExporterPort;
      };

      networking.firewall.extraInputRules = ''
        ip saddr ${net.vmAddress.monitoring} tcp dport ${toString net.nodeExporterPort} accept
      '';
    })
  ];
}
