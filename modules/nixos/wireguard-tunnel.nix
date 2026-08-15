# The point-to-point tunnel described by host.wireguardTunnel: wg0 carrying this system's address and a single peer, with the private key from this host's sops. The listening end opens its port; the dialing end holds the tunnel open with keepalives.
{
  config,
  lib,
  ...
}: let
  wg = config.host.wireguardTunnel;
in {
  networking.firewall.allowedUDPPorts = lib.optionals (wg.listenPort != null) [wg.listenPort];

  networking.wg-quick.interfaces.wg0 = {
    address = ["${wg.local.ip}/${wg.prefixLength}"];
    inherit (wg) listenPort;
    privateKeyFile = config.sops.secrets."wireguard-private-key".path;
    peers = [
      {
        inherit (wg.peer) publicKey endpoint;
        allowedIPs = ["${wg.peer.ip}/32"];
        persistentKeepalive = lib.mkIf (wg.peer.endpoint != null) 25;
      }
    ];
  };
}
