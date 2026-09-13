{
  config,
  lib,
  ...
}: let
  wg = config.host.wireguardTunnel;
in {
  sops.secrets."wireguard-private-key".restartUnits = ["wg-quick-wg0.service"];

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
