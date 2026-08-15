# The tuwunel Matrix homeserver, bound to loopback behind Caddy, with its registration token injected from sops.
{config, ...}: {
  # Registration is open but token-gated. The token is injected via an env var so it doesn't appear in the world-readable tuwunel config file.
  sops.templates."tuwunel.env".content = ''
    TUWUNEL_REGISTRATION_TOKEN=${config.sops.placeholder."tuwunel-registration-token"}
  '';

  systemd.services.tuwunel.serviceConfig.EnvironmentFile = config.sops.templates."tuwunel.env".path;

  services.matrix-tuwunel = {
    enable = true;
    settings.global = {
      server_name = "bunny.enterprises";
      port = [6167];
      # Loopback only. Caddy proxies inbound traffic.
      address = ["::1"];
      allow_registration = true;
      allow_federation = true;
      allow_encryption = true;
    };
  };
}
