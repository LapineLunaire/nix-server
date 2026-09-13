{config, ...}: {
  imports = [
    (let
      tokenSecret = config.host.dnsApiTokenSecret;
    in {
      sops.secrets.${tokenSecret} = {};
      sops.templates."acme-dns-api-token.env" = {
        content = ''
          CF_DNS_API_TOKEN=${config.sops.placeholder.${tokenSecret}}
        '';
        owner = "acme";
      };
    })
  ];

  security.acme = {
    acceptTerms = true;
    defaults = {
      # Match the issuer allowed by the zones' CAA records.
      server = "https://acme-v02.api.letsencrypt.org/directory";
      email = config.host.acmeEmail;
      keyType = "ec384";
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme-dns-api-token.env".path;
    };
  };
}
