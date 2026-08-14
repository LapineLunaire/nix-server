# sparxie's public Caddy vhosts: the bunny.enterprises site and Element.
{
  config,
  pkgs,
  ...
}: let
  element-web = pkgs.element-web.override {
    conf.default_server_config."m.homeserver" = {
      base_url = "https://matrix.bunny.enterprises";
      server_name = "bunny.enterprises";
    };
  };

  inherit (config.caddy) securityHeaders tlsDns;
  # Every vhost opens with its own Caddy-issued certificate and the shared security headers.
  mkVhost = body: {
    extraConfig =
      ''
        ${tlsDns}
        ${securityHeaders}
      ''
      + body;
  };
in {
  services.caddy.virtualHosts = {
    "bunny.enterprises" = mkVhost ''
      root * ${pkgs.bunny-web}

      @hostMeta path /.well-known/host-meta
      header @hostMeta Content-Type "application/xrd+xml"
      header @hostMeta Access-Control-Allow-Origin "*"

      @hostMetaJson path /.well-known/host-meta.json
      header @hostMetaJson Content-Type "application/jrd+json"
      header @hostMetaJson Access-Control-Allow-Origin "*"

      @matrix path /.well-known/matrix/*
      header @matrix Content-Type "application/json"
      header @matrix Access-Control-Allow-Origin "*"

      file_server
    '';
    "chat.bunny.enterprises" = mkVhost ''
      root * ${element-web}
      file_server
    '';
  };
}
