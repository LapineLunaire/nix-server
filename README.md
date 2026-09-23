# nix-server

Carmilla's NixOS servers. The desktop configuration lives in `nix-desktop`.

| Host | Platform | Role |
|------|----------|------|
| sparkle | x86_64-linux | Home server with 16 microVM guests |
| sparxie | aarch64-linux | Public VPS |

Both hosts use nixos-26.05, a tmpfs root and persistent ZFS datasets. Guest state lives under Sparkle's `/persist/vms/`. SOPS secrets use each system's SSH host key; guest secrets also admit Sparkle's key. The default package set uses the stable pin; Lanzaboote and UniFi also use dependencies from the unstable input.

## Usage

From this checkout on either server:

```sh
nix develop
nh os switch .
```

The development shell enables `.githooks/pre-commit`, which checks staged Nix formatting when Alejandra is available. User profiles prefer uutils; system packages and guests retain GNU utilities. On a host, the `sops` shell alias derives the age identity from its SSH host key.

Both hosts check for signed updates daily at 03:00 UTC, with up to 15 minutes of jitter. They verify `origin/main` and hard-reset `/persist/nix-config` to that commit, discarding tracked local edits. Sparxie may reboot when the kernel, kernel modules or initrd change. Sparkle restarts changed running guests after a successful upgrade; boot changes need a manual reboot and, for its encrypted pool, an interactive unlock.

The Forgejo workflow is scheduled daily at 00:00 UTC and also supports manual runs. It refreshes the Home Assistant image digest on Mondays and manual runs. A changed digest triggers evaluation of both hosts and all guests, a build of Sparkle's closure, and a signed commit and push.

The subsequent job updates the lockfile; when it changes, the job also checks the Caddy plugin source hash, evaluates and builds, optionally uploads to Attic when a token is configured, then signs and pushes the update. Sparxie's ARM closure is evaluated but not built by this runner.

A build may finish after the hosts' update checks; a later push is eligible for their next successful check.

## Layout

```text
flake.nix          Inputs, hosts, guests and exported modules
hosts/             Hardware, networking, services and secrets
modules/           Shared NixOS settings and service modules
users/carmilla/    Account and Home Manager configuration
pkgs/              The bunny.enterprises site
overlays.nix       Local package overlay
docs/              Installation, guest operations and network access
.forgejo/          Update workflow and signed commit action
.githooks/         Staged Nix formatting check
.sops.yaml         Secret recipient rules
```

Use relative imports and keep bindings near their consumers. Share settings with multiple consumers, keep host-specific values with the host, and comment on constraints or workarounds. Format Nix with Alejandra.

## Host notes

SSH uses keys only; full hosts disable root SSH login. Sparkle restricts SSH to trusted client subnets and Uptime Kuma's availability check; Sparxie uses a secret IP allowlist. Escalation uses doas.

Sparkle is configured for Lanzaboote Secure Boot; firmware key enrollment and enforcement must be checked on the machine. The installation procedure creates an encrypted Sparkle pool with an interactive unlock and an unencrypted Sparxie pool. Encryption properties live on the pools, not in these filesystem declarations. The vault guest loads its separate pool's key from SOPS. Keep its recovery passphrase separately.

Borg backs up snapshots of each host's `persist` dataset, excluding guest `volumes/` directories. It does not back up `/home`, `/nix`, or the vault guest's separate pool.

See [installation](docs/install.md), [guest operations](docs/guests.md), and [network access](docs/network.md) for the operational details.
