{
  config,
  lib,
  pkgs,
  ...
}: {
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
      }
    '';
    description = "Caddy snippet putting the vhost's certificate on the Cloudflare DNS-01 challenge, spliced into every vhost by the host's proxy config.";
  };

  config = let
    tokenSecret = config.host.dnsApiTokenSecret;
  in {
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    services.caddy.enable = true;

    services.caddy.package = pkgs.caddy.withPlugins {
      plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
      hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
    };

    sops.secrets.${tokenSecret} = {};
    # Caddy uses CF_API_TOKEN; lego uses CF_DNS_API_TOKEN.
    sops.templates."caddy-dns-api-token.env" = {
      restartUnits = ["caddy.service"];
      content = ''
        CF_API_TOKEN=${config.sops.placeholder.${tokenSecret}}
      '';
      owner = "caddy";
    };
    services.caddy.environmentFile = config.sops.templates."caddy-dns-api-token.env".path;

    services.caddy.email = config.host.acmeEmail;
    # CAA permits only Let's Encrypt DNS-01 issuance from the registered accounts.
    services.caddy.globalConfig = ''
      key_type p384
      cert_issuer acme {
        dir https://acme-v02.api.letsencrypt.org/directory
      }
    '';
  };
}
