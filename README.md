# nix-server

Carmilla's NixOS 26.05 servers. Desktop and macOS configuration lives in `nix-desktop`.

| Host | Platform | Role |
|---|---|---|
| sparkle | x86_64-linux | Home server, 16 microVM guests |
| sparxie | aarch64-linux | Public VPS |

## Apply changes

Both hosts keep their checkout at `/persist/nix-config`. Run from there:

```sh
nh os switch .
```

A manual switch does not restart guests. Restart each changed guest with `doas systemctl restart microvm@<name>`.

On a host, the `sops` shell alias derives the age identity from the SSH host key, so `sops hosts/<hostname>/secrets.yaml` decrypts with that key.

## Check changes

```sh
nix develop
nix fmt --no-write-lock-file -- --check .
nix flake check --all-systems --no-build --no-write-lock-file --option allow-import-from-derivation false
```

Entering the development shell sets this clone's hook path to `.githooks`. The pre-commit hook checks staged Nix files with Alejandra and skips the check when Alejandra is not on PATH. The flake check evaluates both hosts and all guests, including assertions, without building or activating them. It does not test secrets or network access; check those on the host. The [validation workflow](.forgejo/workflows/validate.yml) runs the same two checks on pushes to `main`, on pull requests, and on manual dispatch.

## Nightly updates

| UTC | Event |
|---|---|
| 00:00 | CI store reset |
| 00:15 | [Server update workflow](.forgejo/workflows/flake-update.yml) |
| 02:30 | Host upgrades, with up to 15 minutes of jitter |
| 03:30 | Desktop update workflow; Sparkle backup |
| 04:00 | Sparxie backup |
| 12:00 | Borg freshness check |

On Mondays and manual runs, the `digests` job refreshes the Home Assistant image digest; when it changes, the job evaluates all systems, builds Sparkle, and pushes a signed commit. After it succeeds, the `update` job updates `flake.lock`. When the lock changes, it refreshes the Caddy plugin hash if needed, evaluates all systems, builds Sparkle but not Sparxie, uploads the closure to the `server` Attic cache, and pushes a signed commit. Without `ATTIC_TOKEN`, the job skips the upload; with it, an upload failure blocks the push.

Each host upgrade verifies the signature on `origin/main` and runs `git reset --hard` to that commit in `/persist/nix-config`. This discards uncommitted changes to tracked files and unpushed commits on the checked-out branch. Commit signing is configured only on the desktop, so commit and push from there. Sparxie reboots when the kernel, kernel modules, or initrd change. Sparkle restarts changed running guests; boot changes need a manual reboot and the pool passphrase. A failed upgrade mails the last 50 lines of its log. Commits pushed after the upgrade check wait for the next night.

The reset and upgrade timers do not wait for CI to finish, so they can interrupt long or manual runs.

## Operations

- [Install or recover a host](docs/install.md)
- [Guest management, CI store and backups](docs/guests.md)
- [Network access and public endpoints](docs/network.md)

## Source map

| Path | Contents |
|---|---|
| `flake.nix` | Inputs, hosts and guests |
| `hosts/` | Hardware, networking, services and secrets |
| `modules/` | Shared NixOS settings and service modules |
| `users/carmilla/` | Account and Home Manager |
| `pkgs/`, `overlays.nix` | The bunny.enterprises site and its overlay |
| `.sops.yaml` | Secret recipient rules |
| `.forgejo/` | Workflows and the signed commit action |

Format Nix with Alejandra. Use relative imports and keep bindings near their consumers. Put imports first and keep related options together. Share settings that have several consumers and keep host-specific values with the host. Comments explain constraints and workarounds. Commit subjects use `scope: description`.
