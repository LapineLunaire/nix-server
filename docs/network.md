# Network access

Sparkle bridges sfp0 and the guest taps on dmz0. Its bridge firewall rejects unlisted
forwarded traffic and checks each guest's source MAC and IPv4 address before conntrack.
Traffic to Sparkle itself passes through the host input firewall instead.

`hosts/sparkle/dmz-bridge.nix` and each guest's input rules define the policy.
Guest egress with no explicit destination excludes private networks. Explicit
destination grants may reach private addresses. Check the live rules with
`nft list table bridge dmz` when changing access.
The tables name services; the Nix rules and shared port definitions give their exact ports.

**In from the client networks**, across the router, arriving on `sfp0`. "Trusted" is the four networks in `trusted-subnets.nix`.

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
| attic, authelia, forgejo, vaultwarden, pgadmin, uptime-kuma | postgres | Database connections; Uptime Kuma checks availability only |
| proxy, kavita, qbittorrent | vault | NFSv4 |
| every guest | dns | DNS over TCP and UDP |

**Out off the segment**, per guest, from its own `microvmGuest.egress`. Unscoped "any" flows exclude private space. Explicit destination grants are listed separately.

| Guest | May open |
|---|---|
| postgres, attic, pgadmin | nothing at all |
| dns | DNS over TLS, to 1.1.1.1 and 1.0.0.1 only |
| authelia | SMTP submission |
| proxy | HTTPS; DNS over TCP and UDP; WireGuard to sparxie |
| unifi | HTTP and HTTPS; DNS over TCP and UDP; plus any protocol to the management network |
| qbittorrent | WireGuard, ICMP. Torrent traffic stays inside the confinement namespace |
| uptime-kuma | Any TCP/UDP port, ICMP; also ICMP to 10.69.69.69 |
| vault | SMTP submission; the mDNS/WSD groups; WSD discovery replies to the LAN and the router |
| ci-runner, forgejo, homeassistant, kavita, monitoring, vaultwarden | Any TCP/UDP port, ICMP |

Proxied services are filtered by both the host bridge and the guest input firewall.
UniFi publishes container ports through DNAT, so the host bridge enforces its ingress
policy. Vault restricts discovery to multicast destinations in both firewalls.
