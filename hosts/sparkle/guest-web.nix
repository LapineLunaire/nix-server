# Public web endpoints for the guests behind the proxy guest's Caddy: the subdomain each is served under and the port its service listens on.
# The Caddy vhost, sparkle's forward-chain admission for the guest, and the app's own idea of its URL all read from here, so a rename or a port change lands in one place. Guests served without a vhost are not listed.
let
  domain = "lunaire.moe";
  endpoints = {
    pgadmin = {
      sub = "pga";
      port = 5000;
    };
    authelia = {
      sub = "auth";
      port = 9091;
    };
    uptime-kuma = {
      sub = "up";
      port = 3001;
    };
    forgejo = {
      sub = "git";
      port = 3000;
    };
    vaultwarden = {
      sub = "vw";
      port = 8222;
    };
    monitoring = {
      sub = "gf";
      port = 3000;
    };
  };
in {
  inherit domain endpoints;
  # Per-guest https origin, with no trailing slash.
  origin = builtins.mapAttrs (_: e: "https://${e.sub}.${domain}") endpoints;
  # Per-guest vhost name, the Caddy site address and the label the CNAME is generated from.
  vhost = builtins.mapAttrs (_: e: "${e.sub}.${domain}") endpoints;
}
