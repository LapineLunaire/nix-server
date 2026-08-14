# The host option namespace: deployment parameters each system defines for itself and modules read as config.host.*.
{lib, ...}: {
  options.host = {
    flakePath = lib.mkOption {
      type = lib.types.str;
      description = "Path of this system's flake checkout, which nh and system.autoUpgrade build from.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Account email for ACME certificate registration.";
    };

    dnsApiTokenSecret = lib.mkOption {
      type = lib.types.str;
      description = "Name of the sops secret holding this system's zone-scoped Cloudflare DNS API token, read by the acme and caddy modules.";
    };
  };
}
