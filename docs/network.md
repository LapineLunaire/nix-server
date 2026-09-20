# Network access

Sparkle bridges sfp0 and the guest taps on dmz0. Its bridge firewall rejects unlisted
forwarded traffic and checks each guest's source MAC and IPv4 address before conntrack.
Traffic to Sparkle itself passes through the host input firewall instead.

`hosts/sparkle/dmz-bridge.nix` and each guest's input rules define the policy.
Guest egress with no explicit destination excludes private networks. Explicit
destination grants may reach private addresses. Check the live rules with
`nft list table bridge dmz` when changing access.

**In from the client networks**, across the router, arriving on `sfp0`. "Trusted" is the four networks in `trusted-subnets.nix`.

| Source | Reaches | On |
|---|---|---|
| Trusted | sparkle | tcp 22 (sshd) |
| Trusted | proxy | tcp 80, 443. Each vhost then re-checks the source itself |
| Trusted | forgejo | tcp 22 (git-over-SSH) |
| Trusted | vault | tcp 139, 445 (SMB) |
| Trusted | unifi | tcp 443 (UI, no reverse proxy) |
| Trusted | every guest | ICMP echo |
| LAN and the router only | vault | udp 137, 138; tcp 5357 |
| Any source arriving on sfp0 | vault | udp 5353 to 224.0.0.251; udp 3702 to 239.255.255.250 |
| The DMZ segment | proxy | tcp 80, 443 |
| Any source arriving on sfp0 | dns | tcp/udp 53 |
| The management network | unifi | tcp 8080, 8443, 6789, 8880, 8843; udp 3478, 10001 |

**Between guests**

| Source | Reaches | On |
|---|---|---|
| proxy | each proxied guest | that guest's one port from `guest-web.nix` |
| uptime-kuma, forgejo, pgadmin, ci-runner | proxy | tcp 443 |
| uptime-kuma | unifi | tcp 443 |
| monitoring | every guest, and sparkle | tcp 9100 |
| attic, authelia, forgejo, vaultwarden, pgadmin | postgres | tcp 5432 |
| proxy, kavita, qbittorrent | vault | tcp 2049 (NFSv4) |
| every guest | dns | tcp/udp 53 |

**Out off the segment**, per guest, from its own `microvmGuest.egress`. Unscoped "any" flows exclude private space. Explicit destination grants are listed separately.

| Guest | May open |
|---|---|
| postgres, attic, pgadmin | nothing at all |
| dns | tcp 853, to 1.1.1.1 and 1.0.0.1 only |
| authelia | tcp 587 |
| proxy | tcp 443; tcp/udp 53; udp to sparxie's WireGuard endpoint |
| unifi | tcp 80, 443; tcp/udp 53; plus any protocol to the management network |
| qbittorrent | udp 51820, ICMP. Torrent traffic stays inside the confinement namespace |
| uptime-kuma | any tcp/udp port, ICMP; also ICMP to 10.69.69.69 |
| vault | tcp 587; the mDNS/WSD groups; udp from port 3702 to the LAN and the router |
| ci-runner, forgejo, homeassistant, kavita, monitoring, vaultwarden | any tcp/udp port, ICMP |

Proxied services are filtered by both the host bridge and the guest input firewall.
UniFi publishes container ports through DNAT, so the host bridge enforces its ingress
policy. Vault restricts discovery to multicast destinations in both firewalls.
