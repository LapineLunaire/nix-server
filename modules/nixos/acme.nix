# ACME over Cloudflare DNS-01 via lego, for services that read certificate files off disk. Caddy issues its own for everything it serves.
{config, ...}: let
  tokenSecret = config.host.dnsApiTokenSecret;
in {
  sops.secrets.${tokenSecret} = {};
  sops.templates."acme-dns-api-token.env" = {
    content = ''
      CF_DNS_API_TOKEN=${config.sops.placeholder.${tokenSecret}}
    '';
    owner = "acme";
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      # Named explicitly. The zones' CAA records admit only letsencrypt.org, only dns-01 validation, and only named ACME account URIs.
      server = "https://acme-v02.api.letsencrypt.org/directory";
      email = config.host.acmeEmail;
      keyType = "ec384";
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme-dns-api-token.env".path;
      # Resolve the challenge record against a public resolver. The dns guest answers these zones from its local file, which carries no _acme-challenge record.
      dnsResolver = "1.1.1.1:53";
    };
  };
}
