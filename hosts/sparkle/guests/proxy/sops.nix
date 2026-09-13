{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # Caddy renders the DNS token; wg-quick reads the tunnel key.
    secrets."lunaire-moe-dns-api-token" = {};
    secrets."wireguard-private-key" = {};
  };
}
