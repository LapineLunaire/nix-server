# Caddy fronting each system's services. Hosts define their own vhosts and splice the shared snippets below into each one.
{
  config,
  lib,
  pkgs,
  ...
}: let
  tokenSecret = config.host.dnsApiTokenSecret;
in {
  options.caddy.securityHeaders = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = ''
      header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
      }
    '';
    description = "Caddy snippet with the baseline security headers, spliced into every vhost by the host's proxy config.";
  };

  options.caddy.tlsDns = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = ''
      tls {
        dns cloudflare {env.CF_API_TOKEN}
        resolvers 1.1.1.1
      }
    '';
    description = "Caddy snippet putting the vhost's certificate on the Cloudflare DNS-01 challenge, spliced into every vhost by the host's proxy config. resolvers overrides the system resolver, which on these systems is a split-horizon DNS that never holds the public _acme-challenge record.";
  };

  config = {
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    services.caddy.enable = true;

    services.caddy.package = pkgs.caddy.withPlugins {
      plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
      hash = "sha256-7GoH8YLCoPmPExQxoga2FHB58zQDoZVf1BBwkVi0SsQ=";
    };

    # Also declared by acme.nix; the definitions merge on a host importing both.
    sops.secrets.${tokenSecret} = {};
    # The plugin reads CF_API_TOKEN. lego's template reads CF_DNS_API_TOKEN, so each issuer gets its own rendering of the same secret.
    sops.templates."caddy-dns-api-token.env" = {
      content = ''
        CF_API_TOKEN=${config.sops.placeholder.${tokenSecret}}
      '';
      owner = "caddy";
    };
    services.caddy.environmentFile = config.sops.templates."caddy-dns-api-token.env".path;

    services.caddy.email = config.host.acmeEmail;
    # p384 is the same curve lego is told to use as ec384.
    # Let's Encrypt is named explicitly. The zones' CAA records admit only letsencrypt.org, only dns-01 validation, and only two named ACME account URIs per zone, so issuance from any other account or method is refused at the CA.
    services.caddy.globalConfig = ''
      key_type p384
      cert_issuer acme {
        dir https://acme-v02.api.letsencrypt.org/directory
      }
    '';
  };
}
