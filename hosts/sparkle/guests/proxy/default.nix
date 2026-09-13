{
  net,
  trustedSubnets,
  ...
}: let
  sparxieWan = import ../../../sparxie/wan-net.nix;
in {
  imports = [
    ../../../../modules/nixos/caddy.nix
    ../../../../modules/nixos/wireguard-tunnel.nix
    ./sops.nix
    ./vhosts.nix
  ];

  host.trustedSubnets = trustedSubnets.all;

  host.acmeEmail = "certs@lunaire.eu";
  host.dnsApiTokenSecret = "lunaire-moe-dns-api-token";

  # Connect to Sparxie's listening endpoint.
  host.wireguardTunnel = {
    prefixLength = "31";
    local.ip = "10.73.212.0";
    peer = {
      ip = "10.73.212.1";
      publicKey = "VjVuhnnTEHuGssQOp0iM1yU0BLT34VWm3k00e8tDkSg=";
      endpoint = "${sparxieWan.ipv4}:${toString sparxieWan.wireguardPort}";
    };
  };

  microvm = {
    vcpu = 2;
    mem = 1024;
    initialBalloonMem = 256;
  };

  # Automount so a vault outage affects file requests without stopping every Caddy vhost.
  fileSystems."/srv/misc" = {
    device = "${net.vmAddress.vault}:/vault/misc";
    fsType = "nfs4";
    options = [
      "ro"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.mount-timeout=20"
      "x-systemd.idle-timeout=600"
      "noatime"
    ];
  };

  # Bring up the tunnel before Caddy binds its address.
  systemd.services.caddy.after = ["wg-quick-wg0.service"];
  systemd.services.caddy.wants = ["wg-quick-wg0.service"];

  # Allow HTTPS APIs and DNS-01 propagation checks against public authoritative servers.
  microvmGuest.egress = [
    {
      proto = "tcp";
      ports = [443];
    }
    {
      proto = "udp";
      ports = [53];
    }
    {
      proto = "tcp";
      ports = [53];
    }
    {
      proto = "udp";
      ports = [sparxieWan.wireguardPort];
      destinations = [sparxieWan.ipv4];
    }
  ];
}
