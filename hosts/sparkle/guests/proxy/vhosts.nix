{
  config,
  dmz,
  net,
  tunnelWeb,
  web,
  lib,
  ...
}: {
  services.caddy.virtualHosts = let
    inherit (config.caddy) securityHeaders tlsDns;
    wg = config.host.wireguardTunnel;
    baseAllow = config.host.trustedSubnets;

    # Serve the same read-only share locally and through the WireGuard tunnel.
    miscFileServer = ''
      root * /srv/misc
      file_server browse
    '';
    # Additional callers beyond trusted clients. Uptime Kuma probes through the proxy.
    uptimeKuma = net.vmAddress.uptime-kuma;
    vmVhosts = {
      monitoring.extraAllow = [uptimeKuma];
      # authelia: the forgejo and pgadmin OIDC backchannels, plus uptime-kuma.
      authelia.extraAllow = [net.vmAddress.forgejo net.vmAddress.pgadmin uptimeKuma];
      pgadmin.extraAllow = [uptimeKuma];
      uptime-kuma.extraAllow = [];
      vaultwarden = {
        extraAllow = [uptimeKuma];
        body = ''
          reverse_proxy ${net.vmAddress.vaultwarden}:${toString web.endpoints.vaultwarden.port} {
            header_up X-Real-IP {remote_host}
          }
        '';
      };
      # Allow server clones, CI and health checks.
      forgejo.extraAllow = [dmz.subnet net.vmAddress.ci-runner uptimeKuma];
      # Allow cache access from Sparkle and CI; trusted clients already include the desktop.
      attic.extraAllow = [dmz.subnet];
      homeassistant.extraAllow = [uptimeKuma];
      kavita.extraAllow = [uptimeKuma];
      qbittorrent.extraAllow = [uptimeKuma];
    };
    hostVhosts = {
      "misc.${web.domain}" = {
        extraAllow = [uptimeKuma];
        body = miscFileServer;
      };
    };
    vhosts =
      lib.mapAttrs' (name: v:
        lib.nameValuePair web.vhost.${name} {
          inherit (v) extraAllow;
          body = v.body or "reverse_proxy ${net.vmAddress.${name}}:${toString web.endpoints.${name}.port}";
        })
      vmVhosts
      // hostVhosts;
    mkVhost = _: v: {
      extraConfig = ''
        ${tlsDns}
        ${securityHeaders}
        @not_allowed not remote_ip ${lib.concatStringsSep " " (baseAllow ++ v.extraAllow)}
        respond @not_allowed 403
        ${v.body}
      '';
    };
  in
    lib.mapAttrs mkVhost vhosts
    // {
      # Public file server, reachable only via sparxie over WireGuard.
      "http://${wg.local.ip}:${toString tunnelWeb.port}".extraConfig = miscFileServer;
    };

  networking.firewall.interfaces.wg0.allowedTCPPorts = [tunnelWeb.port];
}
