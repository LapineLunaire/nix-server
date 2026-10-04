# Network access

This page lists configured access only. Check router policy, public DNS, and live services separately.

## Sparkle endpoints

Sparkle is `10.28.33.1` and each guest is `10.28.33.<registry index>`. The DMZ is `10.28.32.0/23` with gateway `10.28.32.1`. Trusted clients are `10.28.64.0/24`, `10.28.96.0/24`, `10.100.0.0/24`, and `10.1.0.0/24`; management is `10.28.16.0/24`.

Internal DNS serves the direct-access names: UniFi at `https://unifi.lunaire.moe` (`10.28.33.26`), SMB at `//vault.lunaire.moe` (`10.28.33.17`), and Git SSH at `git-ssh.lunaire.moe` (`10.28.33.20`). The DNS server is `10.28.33.10`.

These HTTPS names use `.lunaire.moe` and admit trusted clients plus the listed callers. A listed guest also needs a bridge rule to reach proxy; see the guest source table.

| Name | Backend | Additional callers |
|---|---|---|
| `auth` | authelia:9091 | forgejo, pgadmin, uptime-kuma |
| `git` | forgejo:3000 | DMZ, ci-runner, uptime-kuma |
| `cache` | attic:8080 | DMZ |
| `pga` | pgadmin:5000 | uptime-kuma |
| `up` | uptime-kuma:3001 | - |
| `vw` | vaultwarden:8222 | uptime-kuma |
| `kv` | kavita:5000 | uptime-kuma |
| `qbt` | qbittorrent:4000 | uptime-kuma |
| `ha` | homeassistant:8123 | uptime-kuma |
| `gf` | monitoring:3000 | uptime-kuma |
| `misc` | proxy's read-only `/srv/misc` file server | uptime-kuma |

## Sparkle firewall

`sfp0` and the guest taps join `dmz0`. The bridge drops unlisted forwarding, validates guest MAC, IPv4, and ARP source addresses before conntrack, and allows valid ARP and established or related traffic. Traffic to Sparkle itself uses the host input firewall. Inspect the bridge rules with `doas nft list table bridge dmz`.

| Client source | Destination | New flows allowed |
|---|---|---|
| Trusted | sparkle, forgejo | SSH |
| Trusted and DMZ | proxy | HTTP and HTTPS; vhost allowlists also apply |
| Trusted | vault | SMB TCP 139 and 445 |
| Trusted | unifi | HTTPS UI TCP 443 |
| Trusted | All guests | ICMP echo |
| LAN and gateway | vault | NetBIOS UDP 137 and 138; WSD TCP 5357 |
| Any via sfp0 | vault | mDNS to 224.0.0.251; WSD to 239.255.255.250 |
| Any via sfp0 | dns | TCP/UDP 53 |
| Management | unifi | TCP 8080, 8443, 6789, 8880, 8843; UDP 3478, 10001 |

| Guest source | Local destination | New flows allowed |
|---|---|---|
| proxy | Web backends in the HTTPS table | Listed backend ports |
| uptime-kuma, forgejo, pgadmin, ci-runner | proxy | HTTPS |
| uptime-kuma | unifi | HTTPS |
| uptime-kuma | sparkle, forgejo | SSH checks |
| monitoring | sparkle and all guests | Node exporter TCP 9100 |
| attic, authelia, forgejo, vaultwarden, pgadmin, uptime-kuma | postgres | TCP 5432; uptime-kuma has no database role |
| proxy, kavita, qbittorrent | vault | NFSv4 TCP 2049 |
| All guests | dns | TCP/UDP 53 |

Egress rules without a destination exclude `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`, and `169.254.0.0/16`; rules with an explicit destination can reach those ranges. ICMP grants allow echo requests only.

| Guest | Off-segment egress |
|---|---|
| postgres, attic, pgadmin | None |
| dns | DNS-over-TLS to 1.1.1.1 and 1.0.0.1 |
| authelia | SMTP submission |
| proxy | HTTPS; TCP/UDP DNS; WireGuard to Sparxie |
| unifi | HTTP and HTTPS; DNS; any protocol to management |
| qbittorrent | UDP 51820; ICMP echo; the application runs in `qbtvpn` |
| uptime-kuma | Any TCP/UDP; ICMP echo, including 10.69.69.69 |
| vault | SMTP submission; mDNS and WSD groups; WSD replies to the LAN and gateway |
| ci-runner, forgejo, homeassistant, kavita, monitoring, vaultwarden | Any TCP/UDP; ICMP echo |

The rules come from `hosts/sparkle/dmz-bridge.nix`, the guest input firewalls, and `microvmGuest.egress`. The bridge also controls UniFi's DNAT-published container ports and qBittorrent's namespace-forwarded UI.

## Sparxie and public tunnel

| Service | TCP | UDP |
|---|---|---|
| Caddy HTTP and HTTPS | 80, 443 | - |
| Matrix federation | 8448 | - |
| ejabberd XMPP, uploads, file transfers, and TURN | 5222, 5223, 5269, 5443, 7777 | 3478, 49152-49500 |
| WireGuard | - | 47329 |
| SSH | 22 | - |

SSH also requires a source address in the SOPS IPv4 or IPv6 allowlist, including from loopback and tunnel addresses. Recover a stale allowlist through the Hetzner console. The ejabberd admin interface listens on loopback; from an allowlisted address, run `ssh -N -L 5280:127.0.0.1:5280 carmilla@46.225.108.230` and open `http://127.0.0.1:5280/admin/`.

Sparxie serves `pub.bunny.enterprises` over HTTPS with basic auth and proxies it over `wg0` to proxy at `10.73.212.0:9000`, which serves the vault guest's read-only `/vault/misc` NFS export. The proxy firewall allows port 9000 only on `wg0`.

The proxy guest initiates WireGuard to `46.225.108.230:47329` with a 25-second keepalive. Sparxie is `10.73.212.1`, and each peer allows the other's `/32`. Requests to port 9000 travel inside the tunnel, so the bridge sees only the WireGuard UDP flow and needs no TCP 9000 rule.
