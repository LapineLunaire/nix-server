# Ingress for the guests: Caddy serving every vhost, the tunnel sparxie reaches the public file server over, and the misc library it serves, mounted over NFS from the vault guest.
{
  net,
  trustedSubnets,
  outputs,
  ...
}: let
  sparxieWan = import ../../../sparxie/wan-net.nix;
in {
  imports = [
    outputs.nixosModules.caddy
    outputs.nixosModules.wireguard-tunnel
    ./sops.nix
    ./vhosts.nix
  ];

  # Client subnets trusted to reach the vhosts, applied as the base allowlist in vhosts.nix. From trusted-subnets.nix, the same list sparkle reads.
  host.trustedSubnets = trustedSubnets.all;

  # ACME account email and the sops secret holding the Cloudflare DNS-01 token (see modules/nixos/caddy.nix).
  host.acmeEmail = "certs@lunaire.eu";
  host.dnsApiTokenSecret = "lunaire-moe-dns-api-token";

  # The WireGuard tunnel to sparxie. This guest dials out and sparxie listens, so endpoint is set here and listenPort is not.
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

  # The misc library, read-only over NFSv4. Caddy deliberately gets no RequiresMountsFor: it serves every vhost and must not fail to start when the vault guest is down, so the automount confines an outage to requests that touch /srv/misc.
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

  # Caddy binds the tunnel address for the file server vhost, so it must start after the interface is up.
  systemd.services.caddy.after = ["wg-quick-wg0.service"];
  systemd.services.caddy.wants = ["wg-quick-wg0.service"];

  # The Cloudflare API and everything else the guests' vhosts reach over HTTPS, whose addresses move behind CDNs.
  # DNS-01 resolution goes through the dns guest, whose lunaire.moe zone falls through to its forwarder for any name its local file does not answer, _acme-challenge among them. The propagation check that follows queries the zone's authoritative nameservers directly, and their addresses move, so this flow names no destination. TCP as well as UDP, since a truncated answer falls back to it.
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
