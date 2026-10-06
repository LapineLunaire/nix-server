# Installation and recovery

Use a UEFI NixOS installer for the target architecture whose ZFS is not newer than the hosts' ZFS 2.4. On Sparkle, disable Secure Boot enforcement before booting unsigned installation or recovery media. Run commands as root in Bash. Replace every `<placeholder>`; the hostname is `sparkle` or `sparxie`. The examples use `/dev/nvme0n1`, so substitute the actual disk; for `/dev/sda`, the partitions are `/dev/sda1` and `/dev/sda2`. Partitioning and formatting erase it.

## 1. Partition and create datasets

```sh
lsblk
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 1GiB 100%
mkfs.vfat -F32 /dev/nvme0n1p1

zpool create -o ashift=12 -o autotrim=on \
  -O atime=off -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
  -O normalization=formD -O compression=zstd \
  -O encryption=on -O keylocation=prompt -O keyformat=passphrase \
  -O mountpoint=none \
  <hostname> /dev/disk/by-id/<disk>-part2

zfs create <hostname>/nix
zfs create <hostname>/persist
zfs create <hostname>/home
zfs set com.sun:auto-snapshot=true <hostname>/persist <hostname>/home
```

- Sparxie's pool is unencrypted; omit the `encryption`, `keylocation`, and `keyformat` properties.
- For a mirror, partition both disks and replace the final device with `mirror /dev/disk/by-id/<disk1>-part2 /dev/disk/by-id/<disk2>-part2`. The EFI partition is not mirrored.
- `networking.hostId` must differ from every other system's, including the vault guest's. Generate one with `head -c4 /dev/urandom | od -An -tx4 | tr -d ' '`.

## 2. Mount and configure hardware

```sh
mount -t tmpfs -o size=2G,mode=755 none /mnt
mkdir -p /mnt/{boot,nix,persist,home}
mount -o umask=0077 /dev/nvme0n1p1 /mnt/boot
mount -t zfs -o zfsutil <hostname>/nix /mnt/nix
mount -t zfs -o zfsutil <hostname>/persist /mnt/persist
mount -t zfs -o zfsutil <hostname>/home /mnt/home
git clone https://git.lunaire.moe/carmilla/nix-server.git /mnt/persist/nix-config
cd /mnt/persist/nix-config
blkid /dev/nvme0n1p1
```

Forgejo runs on Sparkle. If it is unreachable, clone the GitHub mirror at `https://github.com/LapineLunaire/nix-server.git` instead, then point `origin` at Forgejo, because the nightly upgrade fetches from it:

```sh
git remote set-url origin https://git.lunaire.moe/carmilla/nix-server.git
git remote set-url --push origin ssh://forgejo@git-ssh.lunaire.moe/carmilla/nix-server.git
```

Update the EFI UUID in `hosts/<hostname>/hardware-configuration.nix`, and the dataset names only if the pool name differs from the hostname. If you generated a new host ID, set `networking.hostId` in `hosts/<hostname>/default.nix`. Keep the tmpfs root, `neededForBoot` on `/persist`, and the mount options.

On replacement Sparkle hardware, check the kernel `march` in `hosts/sparkle/default.nix`, the guest PCI passthrough addresses, and `max_phys_bits` in the vault and homeassistant guests. After restoring the host key in section 3, update the NIC MAC addresses in the `network/ipmi0-mac`, `network/sfp0-mac`, and `network/sfp1-mac` values of `hosts/sparkle/secrets.yaml`. On a replacement Sparxie VPS, update `hosts/sparxie/wan-net.nix` and the interface name and gateways in `hosts/sparxie/default.nix`.

## 3. Restore identity and state

Restore the host's SSH key pair to `/mnt/persist/etc/ssh/` and keep the private key root-owned with mode `0600`. With the original key, existing secrets need no changes. To create a new identity instead:

```sh
mkdir -p /mnt/persist/etc/ssh
ssh-keygen -t ed25519 -N '' -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . nixpkgs#ssh-to-age \
  -c ssh-to-age < /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub
```

Set `<hostname>_host` in `.sops.yaml` to the new age recipient. Use the old SSH host private key to re-encrypt the host secrets, replacing `<old-private-key>` with its file path:

```sh
SOPS_AGE_KEY_CMD='ssh-to-age -private-key -i <old-private-key>' \
  nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . nixpkgs#sops nixpkgs#ssh-to-age \
  -c sops updatekeys -y hosts/<hostname>/secrets.yaml
```

For a new Sparkle identity, set `consoleKey` in `flake.nix` to the new SSH public key, and repeat the command for each guest secret file whose creation rule includes `sparkle_host`, using either the old Sparkle key or that guest's key. If the old host key is lost, recreate `hosts/<hostname>/secrets.yaml` from the password manager with every secret that the host's configuration declares. If a guest file has neither key, recreate it too.

Restore guest keys and application state under `/mnt/persist/vms/` before the first boot. For a fresh Sparkle installation, create each guest's SSH key as in [guest provisioning](guests.md#add-a-guest), using `/mnt/persist/vms/<name>/etc/ssh/` in the installer. For guests with SOPS files, update their `vm_*` recipients in `.sops.yaml` and re-encrypt their secret files; both the guest and Sparkle must remain recipients.

Keep passwords and values inserted into configuration templates on one line. File secrets, such as SSH private keys and WireGuard configurations, keep their required multiline format. Follow each application's quoting rules, including Authelia's single-quoted YAML and ejabberd's block scalars. The Attic and Vaultwarden database passwords must be URL-safe, for example `openssl rand -hex 32`. Rotate an application's database password and the matching PostgreSQL role secret together.

## 4. Prepare Secure Boot keys (Sparkle)

Sparxie uses systemd-boot; skip this section.

Restore `/var/lib/sbctl` into `/mnt/persist/var/lib/sbctl`, or create new keys there before installing. In both cases, bind-mount the persisted `/var/lib` into the target so Lanzaboote finds the keys:

```sh
install -d -m 700 /mnt/persist/var/lib/sbctl
mkdir -p /mnt/var/lib
mount --bind /mnt/persist/var/lib /mnt/var/lib
```

For new keys only, create them in the persisted directory. The temporary config sets [sbctl's `keydir` and `guid`](https://github.com/Foxboron/sbctl/blob/0.18/docs/sbctl.conf.5.txt):

```sh
cat > /tmp/sbctl-install.yaml <<'CONFIG'
keydir: /mnt/persist/var/lib/sbctl/keys
guid: /mnt/persist/var/lib/sbctl/GUID
CONFIG
nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . nixpkgs#sbctl \
  -c sbctl --config /tmp/sbctl-install.yaml create-keys
```

## 5. Install, reboot and enroll

```sh
nixos-install --no-root-passwd --flake /mnt/persist/nix-config#<hostname>
chown -R 1000:100 /mnt/persist/nix-config
rm -f /mnt/persist/var/lib/systemd/timers/stamp-nixos-upgrade.timer \
  /mnt/persist/var/lib/systemd/timers/stamp-borgbackup-job-hetzner.timer
cd /
umount -R /mnt
zpool export <hostname>
```

The checkout belongs to `carmilla:users`. Root password login is locked, and root cannot log in over SSH. The host does not force-import its root pool, so export it before rebooting. Removing the timer stamps prevents a recovered host from catching up on a missed upgrade or backup immediately after boot; the next scheduled runs still happen.

Commit signing is configured only on the desktop. Copy the hardware, host ID, and SOPS changes there, commit them signed with a key in `host.autoUpdate.allowedSigners`, and push them to `main` before the next upgrade at 02:30 UTC. The upgrade resets the checkout to `origin/main` and would otherwise revert them.

Run `reboot`. Sparkle asks for the pool passphrase on every boot. Sparxie needs no key enrollment. If Sparkle's firmware does not have its keys enrolled, as with new keys or new hardware, enter Setup Mode in the firmware during that reboot while preserving `dbx`. After boot, run as `carmilla`:

```sh
doas sbctl status
doas sbctl verify
doas sbctl enroll-keys --microsoft
```

`sbctl verify` lists Lanzaboote's `kernel-*.efi` files under `EFI/nixos` as unsigned, which is expected. Enable Secure Boot in firmware, reboot, and confirm that `bootctl status` reports Secure Boot as `enabled (user)` or `enabled (deployed)`.

## 6. Vault pool (Sparkle)

The vault guest imports its own pool through the passed-through SAS HBA. Host Borg backups do not include it. Create or restore it inside the guest:

- The encryption root is `vault`, with `keylocation=prompt` and the passphrase stored in `vault-zfs-key`. Also keep the passphrase outside SOPS. The unlock service overrides the key location only while it loads the key.
- The root and all children use `mountpoint=none`; the configured mounts set the paths.
- The datasets are `vault/carmilla`, `vault/misc`, `vault/misc/library`, and `vault/torrents`.

The datasets are `noauto` mounts that NFS and Samba pull in. Load the key, start both services, and check that all four are separate mounts. Set owners only on fresh datasets, and keep restored owners and ACLs:

```sh
systemctl restart vault-unlock
systemctl start nfs-server samba-smbd
findmnt -t zfs
chown carmilla:users /vault/carmilla /vault/misc /vault/misc/library
chown 3000:3000 /vault/torrents
zfs set com.sun:auto-snapshot=true vault/carmilla vault/misc vault/misc/library vault/torrents
zfs get -r com.sun:auto-snapshot vault
```

Read-only NFS exports squash to UID 1000 and GID 100. The writable torrents export squashes to 3000:3000, so existing torrent content must be writable by that ID. Samba forces `carmilla:users` on the `carmilla` and `misc` shares; the read-only `torrents` share uses the authenticated user's permissions, so `carmilla` needs read access to the torrent content. For a fresh Samba account, run `smbpasswd -a carmilla` in the vault guest's root console. Snapshots stay on this pool.

## Recovery

1. Get the Borg credentials and any missing SOPS values from the password manager. On a configured host, use the [Borg helper](guests.md#borg-backup-and-recovery). In an installer, pass the credentials to Borg directly as shown in item 3.
2. If the host pool is intact, skip formatting. Import and unlock it, mount it as in [section 2](#2-mount-and-configure-hardware) without cloning if the checkout survives, then continue with sections 4 and 5:

   ```sh
   zpool import -N <hostname>
   zfs load-key <hostname> # Sparkle only
   ```

   The installer has a different host ID, so the import fails if the original host did not export the pool. Use `zpool import -f -N <hostname>` only after confirming that no other system has it imported.

3. For replacement storage, follow section 1 and the mount commands from section 2, but clone the repository from Forgejo or the GitHub mirror to `/tmp/nix-config` instead of `/mnt/persist/nix-config`. Put the Borg passphrase, SSH private key, and pinned SSH known-hosts entries in root-owned files with mode `0600`, then enter a shell with the checkout's Borg version:

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

   The restored checkout contains the old hardware identifiers, so repeat the UUID, dataset, and host ID edits from section 2. No archive contains the CI store image. Archives created before the CI database exclusion still contain the ci-runner Nix database; run `rm -rf /mnt/persist/vms/ci-runner/nix/var` before booting.

   Follow sections 3 to 5. Borg does not cover `/home`; restore it from another copy if one exists. After Sparkle boots, restore the vault pool as in section 6.

4. If the vault guest cannot import or unlock its pool automatically, for example because its SOPS key is lost, import and unlock it from the guest's root console. Skip `zpool import` if `zpool list vault` already shows the pool:

   ```sh
   zpool import -N vault
   zfs load-key vault
   systemctl restart vault-unlock
   systemctl start nfs-server samba-smbd
   ```

If another machine still has a pool imported, shut it down or export the pool there before importing. Verify guest mounts and application state before resuming use.
