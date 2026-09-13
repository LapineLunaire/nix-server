{config, ...}: {
  # Keep the registration token out of the Nix store.
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
