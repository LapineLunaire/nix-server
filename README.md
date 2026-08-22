# nix-server

Carmilla's server config: the two machines that run services. The desktops live in their own repo.

| Host | Platform | Role |
|------|----------|------|
| sparkle | x86_64-linux | Home server |
| sparxie | aarch64-linux | VPS |

sparkle runs one microVM guest per service (cloud-hypervisor via microvm.nix): dns, proxy, postgres, pgadmin, authelia, monitoring, uptime-kuma, vault, forgejo, ci-runner, vaultwarden, kavita, qbittorrent, homeassistant, and unifi. They are peers of the other servers on the DMZ: sfp0 is enslaved to the `dmz0` bridge, sparkle carries `10.28.33.1/23` on it, and each guest takes `10.28.33.<index>` from `hosts/sparkle/guest-registry.nix`. Indices 10-19 are the platform: resolution, ingress, data, identity, observability, and storage. Indices 20-29 are what the platform serves. The index is also the vsock CID and the MAC's last octet. dns is authoritative for lunaire.moe and resolves for the whole network; proxy serves every vhost and terminates the tunnel to sparxie; homeassistant owns the host's USB controller through VFIO passthrough for the Zigbee stick, and vault owns the SAS HBA the same way, importing the pool on it and serving it to the guests over NFSv4 and to the clients over SMB. Each guest is its own `nixosConfigurations` output, and every one of them is in sparkle's toplevel closure, which is what the CI eval step checks transitively. A second hypervisor is one entry in the flake's `hypervisors` set plus its own guest data files and `guests/` directory. A guest name declared by two hypervisors is an evaluation error.

Both hosts build against nixos-26.05 and use impermanence with a tmpfs `/`. `/var/lib` and `/var/log` are persisted whole, so a new service needs no persistence entry; everything else on `/` is discarded at reboot unless a module declares it. Secrets are sops-nix encrypted to each host's SSH ed25519 host key, and each VM's secrets are additionally encrypted to sparkle's so the host can rebuild any guest. The checkout lives at `/persist/nix-config` on both hosts, which `host.flakePath` records and which the auto-update resets to the verified origin commit.

## Structure

```
flake.nix       Inputs, the host and guest builders, the module export surface, and every system
hosts/          Per-host hardware, services, secrets, and persistence declarations
  sparkle/dmz-bridge.nix  sparkle's own uplink: sfp0 enslaved to the dmz0 bridge, and its default-drop forward chain
  sparkle/guest-*.nix     The guest registry, its addressing, and the web endpoints
  sparkle/guests/         One directory per guest
modules/        host.nix and nix-settings.nix are imported by hosts and guests alike
  nixos/host-base/   Boot, escalation, locale, firewall, hardening, persistence, temp dirs
  nixos/microvm/     The generic guest framework: the guest base, the host wiring, and guest identity
  nixos/*.nix        Opt-in modules: caddy, zfs, borg, wireguard, auto-update, ip-whitelist, ...
users/carmilla/ The account and its home-manager modules
pkgs/           The bunny.enterprises site Caddy serves
```

Shared modules are reached as `outputs.nixosModules.<name>`, and the two platform-neutral ones as `outputs.modules.<name>`, which works from any nesting depth. The guest data files reach a guest as module arguments set by `mkGuest`, so a guest declares the ones it uses and names `net.vmAddress.postgres`, holding no path to its own location. The module factories that take arguments (`mkBorgBackup`, `mkMicrovmGuest`, `mkMicrovmIdentity`, `mkMicrovmHost`) live under `outputs.lib` instead.

Systems are built against nixos-26.05. The `nixpkgs-unstable` input exists only for the inputs that follow it (rust-overlay, lanzaboote, and unifi-os-server); every NixOS and home-manager module sees the one nixos-26.05 instance.

## Usage

```sh
nh os switch .
```

`nix develop` gives the tools for working on the repo, and direnv enters it from `.envrc` on its own. Its shell hook sets `core.hooksPath`, which is per clone and cannot be carried in the repo, so the tracked hooks apply from the first time the shell is entered.

Editing secrets needs the age key derived from the host key; the `sops` shell alias does that derivation:

```sh
sops hosts/sparkle/secrets.yaml
```

Both hosts auto-upgrade daily at 03:00, refusing to build unless `origin/main` verifies against the trusted signers in `host.autoUpdate.allowedSigners`, then hard-resetting the checkout to that commit. sparxie reboots on kernel changes; sparkle skips the reboot (its disk unlock is interactive) and restarts the guests whose config the switch changed, since a host switch leaves them running their old one.

## MicroVM operations

```sh
# Console into a guest (root over vsock)
microvm -s <name>

# Restart one guest after a host switch
systemctl restart microvm@<name>
```

Adding a VM: give it an entry in `hosts/sparkle/guest-registry.nix` (index 10-99, which becomes the vsock CID, the last MAC octet, and the last address octet, 10.28.33.<index>), create `hosts/sparkle/guests/<name>/`, add its web endpoint to `guest-web.nix` if it is proxied, which generates both its vhost in `guests/proxy/vhosts.nix` and the two firewall rules admitting the proxy to it. Declare any `microvmGuest.egress` it needs or it reaches nothing off-segment, and add any other flows to `hosts/sparkle/dmz-bridge.nix`, whose forward chain is default-drop. A guest that needs storage takes it over NFSv4 from the vault guest: add it to `nfsClients` in `guest-net.nix`, which generates both firewall ends, and give it an export line in `guests/vault/default.nix`. Generate its host key into `/persist/vms/<name>/etc/ssh/`, add the `ssh-to-age` recipient to `.sops.yaml` next to `sparkle_host`, and encrypt its `secrets.yaml` to both.

## Security model

Threat model is device theft, remote compromise of internet-facing services, and accidental key exposure, not insider attacks or multi-tenant isolation.

- SSH is FIDO2 resident keys only, no passwords, root login disabled. sparkle's sshd accepts only the trusted client subnets, which excludes the DMZ the guests share with sparkle, the management network, and the sparxie tunnel: the guests are L2-adjacent to sparkle at `10.28.33.x`, but adjacency isn't trust, and none of them can reach its sshd. sparxie, the only public-internet host, accepts SSH only from the addresses in its `ssh-allowed-ips` secrets and runs fail2ban; a stale whitelist is recovered through the Hetzner console.
- Guests instead permit key-only root login, authorized for sparkle's host key and reached over the vsock console.
- Privilege escalation is `doas`, wheel only, with sudo disabled.
- sparkle persists its host key on a ZFS native-encrypted dataset with an interactive boot passphrase and boots through lanzaboote secure boot with sbctl-enrolled keys. sparxie has no disk encryption and its hypervisor is out of trust scope.
- The `vault` pool is natively encrypted too, but unlocked without a prompt: its passphrase is a sops secret in the vault guest, loaded by `vault-unlock.service` before the datasets mount. The unlock passes the key location to `zfs load-key -L` for that load alone, so the pool keeps whatever `keylocation` it was created with. That is `prompt`, per the recipe below, so importing it anywhere else still asks. That is what leaves the disks recoverable without this guest or its sops key.
- The guests share the DMZ segment with the other servers: sfp0 is a port of the `dmz0` bridge alongside every guest tap. The policy over it is a default-drop **bridge-family** forward chain with one rule per allowed flow, so the allowlist still governs guest-to-guest traffic and everything crossing between a guest and the segment. Both sides of every rule name a bridge port: `sfp0` for the segment, and the guest's own name for its tap. That is why the table is bridge-family, which `dmz-bridge.nix` records. Each guest additionally runs its own default-drop input chain.
- A guest's proxied port accepts the proxy and nothing else, enforced twice and generated in both places: the guest's input accept and the host's forward rule both come from `guest-web.nix`, so neither is hand-maintained and they cannot disagree. Everything a guest exposes beyond that is a hand-written rule in `dmz-bridge.nix`, which is the authority. The shapes are per-guest ports scoped to named client guests (postgres on 5432, the vault guest's NFSv4 on 2049, node_exporter from monitoring), ports scoped to the trusted client subnets (forgejo's git-over-SSH, the vault guest's SMB, its discovery, and the router that repeats it) or to the management network (unifi's AP ports, and its UI to the trusted subnets), and one deliberate open port: the dns guest's 53, unfiltered by source because it resolves for everything inside the perimeter.
- Those trusted client subnets are one list, `hosts/sparkle/trusted-subnets.nix`, read by every place that gates on them: sparkle's own sshd and its forward chain, the proxy guest's per-vhost `remote_ip` allowlists, the vault guest's Samba `hosts allow` and input chain, and forgejo's git-over-SSH. Widening access is one edit, and the copies cannot drift apart.
- Guest egress is default-deny per guest, declared as `microvmGuest.egress` next to the service that needs it and rendered into the forward chain from there. A guest is narrowed to specific ports, source ports, or destinations where its outbound targets are fully determined by configuration. Where they are runtime state, it keeps the reach the service needs. A flow naming no destination still cannot reach private space, so "any port anywhere" is never a path to the LAN or the management network; reaching either takes a destination named explicitly, which lifts that exclusion. The one grant left out of this scheme is the unifi guest's access to the management network, a hand-written forward rule because it names no protocol at all and the declaration takes one per flow. Denied flows are logged with the `guest-egress-drop` prefix.
- The proxy guest issues its own certificates over ACME DNS-01, using the `caddy-dns/cloudflare` plugin and a Cloudflare API token scoped to lunaire.moe; sparxie's Caddy does the same for bunny.enterprises. lego (NixOS `security.acme`) covers the services that read cert files off disk: ejabberd on sparxie, and the unifi guest's RSA cert. All of them name the Let's Encrypt directory explicitly, because the zones carry CAA records restricting issuance to Let's Encrypt, to DNS-01, and to each client's own ACME account.
- Backups are Borg (repokey-blake2 + zstd) to a Hetzner Storage Box, preceded by a ZFS snapshot of `<pool>/persist`.

## Access map

Every flow the guests are permitted, read off the generated ruleset. `dmz-bridge.nix` and each guest's own input chain remain the authority; this is a summary and can go stale, so check it against `nft list table bridge dmz` before trusting it for anything load-bearing.

**In from the client networks**, across the router, arriving on `sfp0`. "Trusted" is the four networks in `trusted-subnets.nix`.

| Source | Reaches | On |
|---|---|---|
| Trusted | sparkle | tcp 22 (sshd) |
| Trusted | proxy | tcp 80, 443. Each vhost then re-checks the source itself |
| Trusted | forgejo | tcp 22 (git-over-SSH) |
| Trusted | vault | tcp 139, 445 (SMB) |
| Trusted | unifi | tcp 443 (UI, no reverse proxy) |
| Trusted | every guest | ICMP echo |
| LAN and the router only | vault | udp 137, 138; tcp 5357; and the mDNS/WS-Discovery groups |
| The DMZ segment | proxy | tcp 80, 443 |
| The management network | unifi | tcp 8080, 8443, 6789, 8880, 8843; udp 3478, 10001 |

**Between guests**

| Source | Reaches | On |
|---|---|---|
| proxy | each proxied guest | that guest's one port from `guest-web.nix` |
| uptime-kuma, forgejo, pgadmin, ci-runner | proxy | tcp 443 |
| uptime-kuma | unifi | tcp 443 |
| monitoring | every guest, and sparkle | tcp 9100 |
| authelia, forgejo, vaultwarden, uptime-kuma, pgadmin | postgres | tcp 5432 |
| proxy, kavita, qbittorrent | vault | tcp 2049 (NFSv4) |
| every guest | dns | tcp/udp 53 |

**Out off the segment**, per guest, from its own `microvmGuest.egress`. "Any" excludes private space throughout, so none of these is a path to the LAN or the management network.

| Guest | May open |
|---|---|
| postgres | nothing at all |
| dns | tcp 853, to 1.1.1.1 and 1.0.0.1 only |
| authelia | tcp 587 |
| pgadmin | tcp 443 |
| proxy | tcp 443; tcp/udp 53; udp to sparxie's WireGuard endpoint |
| unifi | tcp 80, 443; tcp/udp 53; plus any protocol to the management network |
| qbittorrent | udp 51820, ICMP. Torrent traffic stays inside the confinement namespace |
| vault | tcp 587; the mDNS/WSD groups; udp from port 3702 to the LAN and the router |
| ci-runner, forgejo, homeassistant, kavita, monitoring, uptime-kuma, vaultwarden | any tcp/udp port, ICMP |

Two asymmetries worth knowing. Every guest enforces its proxied port twice, in the host's forward chain and its own input chain, except for **unifi**, whose container publishes its ports, so they are DNAT'd past its input chain and the host's forward chain is the only thing gating them. And the **vault** guest's input chain accepts mDNS on 5353 from any source, because avahi's module opens it; what actually scopes it is the forward rule, which matches on the multicast destination.

## Bootstrapping a host

Boot from a NixOS installer ISO, then:

**1. Partition**

```sh
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 1GiB 100%

mkfs.vfat -F32 /dev/nvme0n1p1
```

**2. Create the ZFS pool and its datasets**

```sh
zpool create -o ashift=12 -o autotrim=on \
  -O atime=off -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
  -O normalization=formD -O compression=zstd \
  -O encryption=on -O keylocation=prompt -O keyformat=passphrase \
  -O mountpoint=none \
  <hostname> /dev/disk/by-id/<disk>-part2

zfs create <hostname>/nix
zfs create <hostname>/persist
zfs create <hostname>/home
```

`services.zfs.autoSnapshot` (modules/nixos/zfs.nix) only snapshots datasets carrying the property, so mark them:

```sh
zfs set com.sun:auto-snapshot=true <hostname>/persist <hostname>/home
```

The `vault` pool lives on a SAS HBA passed through to the vault guest, which imports it and serves it; it is never mounted on the host. A freshly created dataset is owned `root:root`, so chown each one once from inside that guest to the identity its export or share squashes to: `chown carmilla:users /vault/misc /vault/carmilla`, and `chown -R 3000:3000 /vault/torrents` for the writable export, whose `all_squash,anonuid=3000` would otherwise leave qbittorrent unable to write.

Omit the three encryption options for an unencrypted pool (sparxie's layout), and replace the vdev with `mirror <disk1>-part2 <disk2>-part2` for a mirror. Each host also needs a unique `networking.hostId`; generate one with `head -c4 /dev/urandom | od -An -tx4 | tr -d ' '`.

**3. Mount**

```sh
mount -t tmpfs -o size=2G,mode=755 none /mnt
mkdir -p /mnt/{boot,nix,persist,home}
mount /dev/nvme0n1p1 /mnt/boot
mount -t zfs -o zfsutil <hostname>/nix /mnt/nix
mount -t zfs -o zfsutil <hostname>/persist /mnt/persist
mount -t zfs -o zfsutil <hostname>/home /mnt/home
```

**4. Generate the SSH host key (required for sops)**

```sh
mkdir -p /mnt/persist/etc/ssh
ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
```

Get the age recipient with `ssh-to-age < /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub`, put it in `.sops.yaml` under `<hostname>_host`, include it in the creation rule for `hosts/<hostname>/secrets.yaml`, and re-encrypt with `sops updatekeys hosts/<hostname>/secrets.yaml`.

**5. Clone the repo and install**

```sh
mkdir -p /mnt/persist/nix-config
git clone <repo> /mnt/persist/nix-config
nixos-install --flake /mnt/persist/nix-config#<hostname>
```

**6. First boot, secure boot hosts only (sparkle)**

```sh
install -d -m 700 /var/lib/sbctl
sbctl create-keys
sbctl enroll-keys --microsoft
```

`sbctl create-keys` writes private keys, so the directory must exist with mode 0700 first. It is persisted from then on.
