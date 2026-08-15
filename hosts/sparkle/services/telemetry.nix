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
}
