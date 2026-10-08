# Recover Sparkle or Sparxie

Use a matching UEFI NixOS installer whose ZFS is not newer than the hosts' ZFS 2.4. On Sparkle, disable Secure Boot enforcement before booting unsigned recovery media. Run commands as root in Bash. Replace every `<placeholder>`; the hostname is `sparkle` or `sparxie`.

Get the Borg credentials and any missing SOPS values from the password manager. On a configured host, use the [Borg helper](guests.md#borg-backup-and-recovery). In an installer, pass the credentials to Borg directly as shown below.

## Existing pool

**Skip all partitioning and formatting.**

If the host pool is intact, skip formatting. Import and unlock it, then [mount the existing datasets](install-servers.md#2-mount-and-configure-hardware) without cloning if the checkout survives:

```sh
zpool import -N <hostname>
zfs load-key <hostname> # Sparkle only
```

The installer has a different host ID, so the import fails if the original host did not export the pool. Use `zpool import -f -N <hostname>` only after confirming that no other system has it imported.

Change into the surviving checkout at `/mnt/persist/nix-config`. Restore [identity and state](keys.md#restore-identity-and-state) if needed, prepare [Sparkle signing keys and the bind mount](secure-boot.md#installer-signing-keys), then [reinstall, remove timer stamps and export](install-servers.md#4-install-and-export).

## Replacement storage and Borg restore

For replacement storage, follow [storage creation](install-servers.md#1-partition-and-create-datasets) and the [mount commands](install-servers.md#2-mount-and-configure-hardware), but clone the repository from Forgejo or the GitHub mirror to `/tmp/nix-config` instead of `/mnt/persist/nix-config`. Put the Borg passphrase, SSH private key, and pinned SSH known-hosts entries in root-owned files with mode `0600`, then enter a shell with the checkout's Borg version:

```sh
nix --extra-experimental-features 'nix-command flakes' shell --inputs-from /tmp/nix-config nixpkgs#borgbackup
export BORG_REPO='<repository-url>'
export BORG_PASSCOMMAND='cat /run/borg-passphrase'
export BORG_RSH='ssh -i /run/borg-ssh-key -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/run/borg-known-hosts'
borg list
```

Adjust the file paths to match the restored credentials. Restore into the mounted `/persist` dataset; `--strip-components 2` removes the archive's `mnt/borg-snapshot/` prefix:

```sh
cd /mnt/persist
borg extract --numeric-ids --strip-components 2 ::<archive> mnt/borg-snapshot
cd /mnt/persist/nix-config
```

The restored checkout contains the old hardware identifiers, so repeat the UUID, dataset, and host ID edits from [hardware configuration](install-servers.md#2-mount-and-configure-hardware). No archive contains the CI store image. Archives created before the CI database exclusion still contain the ci-runner Nix database; run `rm -rf /mnt/persist/vms/ci-runner/nix/var` before booting.

Restore [identity and state](keys.md#restore-identity-and-state), prepare [Sparkle signing keys](secure-boot.md#installer-signing-keys), then [install and export the pool](install-servers.md#4-install-and-export). Borg does not cover `/home`; restore it from another copy if one exists. After Sparkle boots, [restore the vault pool](vault.md#recovery).

## After recovery

After Sparkle boots, re-enable Secure Boot enforcement and [verify it](secure-boot.md#installed-system-enrollment). For vault pool issues, follow [vault recovery](vault.md#recovery).

If another machine still has a pool imported, shut it down or export the pool there before importing. Verify guest mounts and application state before resuming use.
