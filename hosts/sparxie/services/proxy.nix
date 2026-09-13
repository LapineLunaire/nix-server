{
  config,
  lib,
  pkgs,
  ...
}: {
  # 8448: the Matrix federation port for server-to-server traffic.
  networking.firewall.allowedTCPPorts = [8448];

  sops.templates."caddy-pub-bnnuy-basicauth" = {
    owner = "caddy";
    reloadUnits = ["caddy.service"];
    content = ''
      basic_auth {
        bnnuy ${config.sops.placeholder."pub-bnnuy-password-hash"}
      }
    '';
  };

  # Keep the apex in ejabberd's certificate for XMPP identity checks.
  security.acme.certs."bunny.enterprises" = {
    extraDomainNames = [
      "xmpp.bunny.enterprises"
      "conference.bunny.enterprises"
      "proxy.bunny.enterprises"
      "pubsub.bunny.enterprises"
      "upload.bunny.enterprises"
    ];
    # Give ejabberd access to this certificate only.
    group = "bunny-cert";
    # Reload ejabberd's configuration to load renewed certificates.
    reloadServices = ["ejabberd.service"];
  };

  users.groups.bunny-cert = {};
  users.users.ejabberd.extraGroups = ["bunny-cert"];

  services.caddy.virtualHosts = let
    inherit (config.caddy) securityHeaders tlsDns;
    wg = config.host.wireguardTunnel;
    sparkleTunnelWeb = import ../../sparkle/tunnel-web.nix;
    mkVhost = body: {
      extraConfig =
        ''
          ${tlsDns}
          ${securityHeaders}
        ''
        + body;
    };
    tuwunelPort = lib.head config.services.matrix-tuwunel.settings.global.port;
    # Serve HTTPS and federation with the same certificate.
    matrixVhost = mkVhost ''
      reverse_proxy [::1]:${toString tuwunelPort}
    '';
  in {
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
    "chat.bunny.enterprises" = let
      element-web = pkgs.element-web.override {
        conf.default_server_config."m.homeserver" = {
          base_url = "https://matrix.bunny.enterprises";
          server_name = "bunny.enterprises";
        };
      };
    in
      mkVhost ''
        root * ${element-web}
        file_server
      '';
    "matrix.bunny.enterprises" = matrixVhost;
    "matrix.bunny.enterprises:8448" = matrixVhost;
    "pub.bunny.enterprises" = mkVhost ''
      import ${config.sops.templates."caddy-pub-bnnuy-basicauth".path}
      reverse_proxy ${wg.peer.ip}:${toString sparkleTunnelWeb.port} {
        header_up Host {upstream_hostport}
      }
    '';
  };
}
