# The fleet's Caddy vhosts: one per proxied guest plus the misc file server, each behind a source-IP allowlist and its own Caddy-issued certificate, and the plain-HTTP file server sparxie reaches over the tunnel.
{
  config,
  net,
  tunnelWeb,
  web,
  lib,
  ...
}: let
  inherit (config.caddy) securityHeaders tlsDns;
  wg = config.host.wireguardTunnel;
  # Source-IP base allowlist applied to every vhost: the trusted client subnets.
  baseAllow = config.host.trustedSubnets;

  # The misc share browsed over HTTP, served both as a proxied vhost and directly on the tunnel address below. Read-only NFS from the vault guest.
  miscFileServer = ''
    root * /srv/misc
    file_server browse
  '';
  # One vhost per proxied guest, keyed by guest name. The site address and the upstream port come from the fleet's web endpoints, and the dns guest generates a zone CNAME per vhost. extraAllow lists callers beyond baseAllow; body overrides the default reverse proxy to the guest.
  vmVhosts = {
    monitoring.extraAllow = [];
    authelia.extraAllow = [];
  };
  # Vhosts this guest serves itself, keyed by full site address since they have no upstream behind them.
  hostVhosts = {
    "misc.${web.domain}" = {
      extraAllow = [];
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
in {
  services.caddy.virtualHosts =
    lib.mapAttrs mkVhost vhosts
    // {
      # Public file server, reachable only via sparxie over WireGuard.
      "http://${wg.local.ip}:${toString tunnelWeb.port}".extraConfig = miscFileServer;
    };

  networking.firewall.interfaces.wg0.allowedTCPPorts = [tunnelWeb.port];
}
