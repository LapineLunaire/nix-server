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
    kavita = {
      sub = "kv";
      port = 5000;
    };
    qbittorrent = {
      sub = "qbt";
      port = 4000;
    };
    homeassistant = {
      sub = "ha";
      port = 8123;
    };
    monitoring = {
      sub = "gf";
      port = 3000;
    };
    attic = {
      sub = "cache";
      port = 8080;
    };
  };
in {
  inherit domain endpoints;
  origin = builtins.mapAttrs (_: e: "https://${e.sub}.${domain}") endpoints;
  vhost = builtins.mapAttrs (_: e: "${e.sub}.${domain}") endpoints;
}
