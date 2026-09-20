# Network access

This describes the configured allowances. Router policy, public DNS and the current state of services must be checked separately when diagnosing reachability.

## Sparkle

Sparkle bridges sfp0 and the guest taps on dmz0. Its bridge firewall drops unlisted forwarded traffic and checks each guest's source MAC, IPv4 source and ARP sender address before conntrack. It permits ARP after these checks and established or related traffic; the tables below describe allowances for new IPv4 flows. Traffic to Sparkle itself passes through the host input firewall instead.

`hosts/sparkle/dmz-bridge.nix` and each guest's input rules define the policy. Guest egress with no explicit destination excludes `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10` and `169.254.0.0/16`. Explicit destination grants may reach those ranges.

Check the live rules as root with `nft list table bridge dmz` when changing access. The tables name services; the Nix rules and shared port definitions give their exact ports.

**In from client networks**, arriving on `sfp0`. Routed clients need access through their router as well. "Trusted" is the four networks in `trusted-subnets.nix`: `10.28.64.0/24`, `10.28.96.0/24`, `10.100.0.0/24` and `10.1.0.0/24`.

| Source | Reaches | Service or traffic |
|---|---|---|
| Trusted | sparkle | SSH |
| Trusted | proxy | HTTP and HTTPS. Each vhost then re-checks the source itself |
| Trusted | forgejo | Git over SSH |
| Trusted | vault | SMB |
| Trusted | unifi | HTTPS UI, no reverse proxy |
| Trusted | every guest | ICMP echo |
| LAN and the router only | vault | NetBIOS discovery and WSD metadata |
| Any source arriving on sfp0 | vault | mDNS to 224.0.0.251; WSD discovery to 239.255.255.250 |
| The DMZ segment | proxy | HTTP and HTTPS |
| Any source arriving on sfp0 | dns | DNS over TCP and UDP |
| The management network | unifi | Controller adoption, management and device services |

**From guests to local services**

| Source | Reaches | Service or traffic |
|---|---|---|
| proxy | each proxied guest | Web backend defined in `guest-web.nix` |
| uptime-kuma, forgejo, pgadmin, ci-runner | proxy | HTTPS |
| uptime-kuma | unifi | HTTPS UI |
| uptime-kuma | sparkle, forgejo | SSH availability checks |
| monitoring | every guest, and sparkle | Node exporter metrics |
| attic, authelia, forgejo, vaultwarden, pgadmin, uptime-kuma | postgres | PostgreSQL port; Uptime Kuma has network access for availability checks, but no configured database role |
| proxy, kavita, qbittorrent | vault | NFSv4 |
| every guest | dns | DNS over TCP and UDP |

**Out off the segment**, from `microvmGuest.egress`, plus the bridge's explicit UniFi management-network grant. Unscoped flows exclude the five ranges above. "ICMP echo" means outgoing echo requests; it does not grant arbitrary ICMP types.

| Guest | May open |
|---|---|
| postgres, attic, pgadmin | No new off-segment flows; local allowances above still apply |
| dns | DNS over TLS, to 1.1.1.1 and 1.0.0.1 only |
| authelia | SMTP submission |
| proxy | HTTPS; DNS over TCP and UDP; WireGuard to sparxie |
| unifi | HTTP and HTTPS; DNS over TCP and UDP; plus any protocol to the management network |
| qbittorrent | UDP 51820 for WireGuard; ICMP echo. qBittorrent runs in the `qbtvpn` network namespace |
| uptime-kuma | Any TCP/UDP port, ICMP echo; also ICMP echo to 10.69.69.69 |
| vault | SMTP submission; the mDNS/WSD groups; WSD discovery replies to the LAN and the router |
| ci-runner, forgejo, homeassistant, kavita, monitoring, vaultwarden | Any TCP/UDP port, ICMP echo |

The bridge filters proxy-to-backend traffic. Ordinary guest listeners also use the guest input firewall; qBittorrent's Web UI is forwarded into its VPN namespace, with the bridge restricting access to the proxy guest.

UniFi publishes container ports through DNAT, so the host bridge enforces its ingress policy.

Vault's mDNS and multicast WSD allowances match multicast destinations in both firewalls; its separate NetBIOS, WSD metadata and WSD reply rules permit the listed unicast traffic.

## Sparxie and the inbound tunnel

Sparxie's host firewall allows these public-facing ports. This lists configured port allowances, not a live socket inventory; TURN relay sockets are allocated as needed.

| Service | TCP | UDP | Configuration |
|---|---|---|---|
| ejabberd: XMPP, HTTPS uploads, SOCKS5 transfers and STUN/TURN | 5222, 5223, 5269, 5443, 7777 | 3478, 49152-49500 | `hosts/sparxie/services/ejabberd.nix` |
| Matrix federation through Caddy | 8448 | - | `hosts/sparxie/services/proxy.nix` |
| Caddy HTTP and HTTPS | 80, 443 | - | `modules/nixos/caddy.nix` |
| WireGuard | - | 47329 | `hosts/sparxie/wan-net.nix`, `modules/nixos/wireguard-tunnel.nix` |
| SSH | 22 | - | `modules/nixos/host-base/default.nix`, `modules/nixos/ssh-ip-whitelist.nix` |

SSH is additionally gated by the SOPS-backed IPv4 and IPv6 allowlists, including connections from loopback and the tunnel. These rules drop unlisted sources before the normal host input firewall. ejabberd's HTTP administration listener on TCP 5280 is bound to `127.0.0.1` and is not publicly opened. Sparxie also enables a Fail2ban SSH jail, which can temporarily ban an otherwise allowlisted source.

`pub.bunny.enterprises` terminates HTTPS at Sparxie's Caddy, requires basic authentication, and reverse-proxies over `wg0` to `http://10.73.212.0:9000` in Sparkle's proxy guest. That listener serves `/srv/misc` with directory browsing; the directory is a read-only NFS mount of Vault's `/vault/misc`. The guest permits TCP 9000 only on `wg0`, and its Caddy listener uses the tunnel address.

The proxy guest initiates WireGuard to Sparxie at `46.225.108.230:47329`, with a 25-second persistent keepalive. Sparxie's tunnel address is `10.73.212.1`; each peer allows only the other peer's `/32`. The bridge admits returning tunnel packets through its established-connection rule. The public file-server request travels inside that tunnel; it is not a public TCP 9000 opening on Sparkle's bridge.
