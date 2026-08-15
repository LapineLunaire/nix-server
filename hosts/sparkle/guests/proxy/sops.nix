{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # Read by the caddy module's rendering of the Cloudflare token, and by the tunnel's wg-quick unit.
    secrets."lunaire-moe-dns-api-token" = {};
    secrets."wireguard-private-key" = {};
  };
}
