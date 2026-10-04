# Guest operations

## Console and restart

Run on Sparkle:

```sh
doas microvm -s <name>
doas systemctl restart microvm@<name>
```

`microvm -s` opens a root shell over VSOCK, authenticated with Sparkle's SSH host key. A manual host switch installs new guest runners without restarting the guests; the nightly upgrade restarts changed running guests. The `deps` entries in `hosts/sparkle/guest-registry.nix` order startup but do not wait for the applications to become ready.

## Add a guest

1. Add its directory under `hosts/sparkle/guests/` and a unique index from 10 to 99 in `hosts/sparkle/guest-registry.nix`. Do not change existing indices, because they determine each guest's IP address, VSOCK CID, and hexadecimal MAC suffix.
2. Add web backends to `hosts/sparkle/guest-web.nix`, which also generates the DNS records and the firewall rules between proxy and the guest. Add access policies to `hosts/sparkle/guests/proxy/vhosts.nix`. Declare `microvmGuest.egress`, and add any other ingress to `hosts/sparkle/dmz-bridge.nix` and the guest firewall. See [network access](network.md).
3. For NFS, update `nfsClients` in `hosts/sparkle/guest-net.nix`, the guest's mount, and the vault guest's export.
4. Restore the guest's keys and state, or create its identity as root:

   ```sh
   mkdir -p /persist/vms/<name>/etc/ssh
   ssh-keygen -t ed25519 -N '' -f /persist/vms/<name>/etc/ssh/ssh_host_ed25519_key
   ```

   For SOPS, convert the public key with `ssh-to-age`, add the recipient and a creation rule to `.sops.yaml`, and encrypt the secrets for both the guest and Sparkle. Keep restored keys and numeric owners; image directories use `microvm:kvm` with mode `0750`. Initialize new application state before use. For secret value formats, see [restore identity and state](install.md#3-restore-identity-and-state).

Stage new files with `git add` before evaluating or switching, because a Git-backed flake omits untracked files. Commit and push the guest before the next nightly upgrade, which resets the checkout to `origin/main`.

## CI store

The ci-runner guest runs the `nixos` Forgejo Actions jobs for nix-server and nix-desktop and substitutes from the `server` and `desktop` caches.

Guests mount the host store read-only at `/nix/.ro-store` and write to an overlay upper layer at `/nix/.rw-store`, which most guests keep on the tmpfs root. ci-runner keeps it on a persistent 128 GiB XFS image and persists `/nix/var`. Do not run garbage collection inside ci-runner, because overlay whiteouts can hide host store paths that later generations need.

The nightly reset stops ci-runner, deletes its store image and its Nix database, and starts it again. A missed reset waits for the next night. Missing store paths are fetched from the caches or rebuilt. See the [nightly schedule](../README.md#nightly-updates).

## Borg backup and recovery

Both hosts back up a snapshot of `/persist` and keep 7 daily, 4 weekly, and 3 monthly archives. Borg does not cover `/home` or the vault pool; `nixos-install` recreates `/nix`.

Sparkle's backup excludes:

- `/persist/vms/*/volumes/`: the ci-runner store, build, and swap images, and the homeassistant and unifi container images.
- `/persist/vms/ci-runner/nix/var`: the ci-runner Nix database, which describes the excluded store image.

Home Assistant's bind-mounted `/config` and UniFi's `/var/lib/unifi-os-server` stay in the backup. Preserve numeric owners when restoring. Archives created before the database exclusion contain `mnt/borg-snapshot/vms/ci-runner/nix/var`; delete it after restoring and before starting ci-runner.

The `borg-job-hetzner` helper reads the repository, passphrase, SSH key, and pinned host key from the SOPS secrets at runtime:

```sh
doas borg-job-hetzner list
doas borg-job-hetzner info ::<archive>
doas borg-job-hetzner check
```

The backup job does not create repositories. Initialize a new one with:

```sh
doas borg-job-hetzner init --encryption repokey-blake2
```

Extract into a separate directory, stop the affected services or guests, then copy the selected state into `/persist`. Archive paths begin with `mnt/borg-snapshot/`:

```sh
mkdir -p ~/borg-restore
cd ~/borg-restore
doas borg-job-hetzner extract --numeric-ids ::<archive> mnt/borg-snapshot/vms/<name>
```

For a full host recovery, see [Recovery](install.md#recovery).

A failed backup, including one that ends with Borg warnings, mails the last 50 lines of the job log. Only a run that completes creation, pruning, and compaction records success. A daily check at 12:00 UTC mails when the last recorded success is more than 24 hours old or missing. To inspect the job:

```sh
doas systemctl status borgbackup-job-hetzner.timer borgbackup-job-hetzner.service
doas journalctl -u borgbackup-job-hetzner -n 50 --no-pager
```
