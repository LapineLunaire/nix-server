# sparxie's public Caddy vhosts: the bunny.enterprises site and Element.
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
    content = ''
      basic_auth {
        bnnuy ${config.sops.placeholder."pub-bnnuy-password-hash"}
      }
    '';
  };

  # ejabberd reads this cert off disk, so lego issues it. The apex must stay in it, since bunny.enterprises is the XMPP host and c2s and s2s identity depend on it. Caddy issues the apex web vhost a separate certificate of its own.
  security.acme.certs."bunny.enterprises" = {
    # One SAN certificate covering every ejabberd component subdomain: conference (MUC), proxy (SOCKS5 file transfer), pubsub, and upload (HTTP upload).
    extraDomainNames = [
      "xmpp.bunny.enterprises"
      "conference.bunny.enterprises"
      "proxy.bunny.enterprises"
      "pubsub.bunny.enterprises"
      "upload.bunny.enterprises"
    ];
    # A dedicated group for this cert's files, so ejabberd can read this one and no other.
    group = "bunny-cert";
    # ejabberd loads the cert files at startup and re-reads them only on restart, so reload it when this cert renews.
    reloadServices = ["ejabberd.service"];
  };

  users.groups.bunny-cert = {};
  users.users.ejabberd.extraGroups = ["bunny-cert"];

  services.caddy.virtualHosts = let
    element-web = pkgs.element-web.override {
      conf.default_server_config."m.homeserver" = {
        base_url = "https://matrix.bunny.enterprises";
        server_name = "bunny.enterprises";
      };
    };

    inherit (config.caddy) securityHeaders tlsDns;
    wg = config.host.wireguardTunnel;
    sparkleTunnelWeb = import ../../sparkle/tunnel-web.nix;
    # Every vhost opens with its own Caddy-issued certificate and the shared security headers.
    mkVhost = body: {
      extraConfig =
        ''
          ${tlsDns}
          ${securityHeaders}
        ''
        + body;
    };
    # The port tuwunel.nix binds the homeserver to, on the loopback address it listens on there.
    tuwunelPort = lib.head config.services.matrix-tuwunel.settings.global.port;
    # Federation on 8448 and HTTPS on 443 serve the same homeserver behind the same certificate.
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
    "chat.bunny.enterprises" = mkVhost ''
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
