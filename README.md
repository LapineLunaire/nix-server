# nix-server

Carmilla's NixOS servers. The desktop configuration lives in `nix-desktop`.

| Host | Platform | Role |
|------|----------|------|
| sparkle | x86_64-linux | Home server with 16 microVM guests |
| sparxie | aarch64-linux | Public VPS |

Both hosts use nixos-26.05, a tmpfs root and persistent ZFS datasets. Guest state
lives under Sparkle's `/persist/vms/`. SOPS secrets use each system's SSH host key;
guest secrets also admit Sparkle's key. The unstable input supplies dependencies
for Lanzaboote and UniFi; system packages stay on the stable pin.

## Usage

```sh
nix develop
nh os switch .
```

The development shell installs the formatting hook. User profiles prefer uutils;
system packages and guests retain GNU utilities. On a host, the `sops` shell alias
derives the age identity from its SSH host key.

Both hosts check for signed updates daily at 03:00 and reset `/persist/nix-config`
to the verified origin commit. Sparxie may reboot for kernel changes. Sparkle
restarts changed guests and needs a manual reboot and disk unlock for kernel updates.

The Forgejo workflow runs at 02:00. It refreshes container digests on Mondays,
updates the lockfile, evaluates both hosts and all guests, and builds Sparkle's
closure. It uploads to Attic when a token is configured, then signs and pushes
the update. Sparxie's ARM closure is evaluated but not built by this runner.

## Layout

```text
flake.nix          Inputs, hosts, guests and exported modules
hosts/             Hardware, networking, services and secrets
modules/           Shared NixOS settings and service modules
users/carmilla/    Account and Home Manager configuration
pkgs/              The bunny.enterprises site
overlays.nix       Local package overlay
docs/              Installation, guest operations and network access
```

Use relative imports and keep bindings near their consumers. Share settings with
multiple consumers, keep host-specific values with the host, and comment on
constraints or workarounds. Format Nix with Alejandra.

## Host notes

SSH uses keys only; full hosts disable root login. Sparkle restricts SSH to trusted
client subnets, and Sparxie uses a secret IP allowlist. Escalation uses doas.
Sparkle uses Secure Boot and an interactive ZFS unlock. The vault guest unlocks
its separate encrypted pool from SOPS. Keep its recovery passphrase separately.
Sparxie's disks are unencrypted. Borg backs up snapshots of each host's persist dataset.

See [installation](docs/install.md), [guest operations](docs/guests.md), and
[network access](docs/network.md) for the operational details.
