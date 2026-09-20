# Installation

Boot a NixOS installer for the target architecture in UEFI mode, with ZFS support, and run the installation commands as root in Bash. The examples use `/dev/nvme0n1`; substitute the target disk on Sparxie. Partitioning and formatting erase that disk. Replace `<hostname>` with `sparkle` or `sparxie`, and replace all other angle-bracket placeholders before running commands. Use an installer whose ZFS pool features are supported by the target system.

**1. Partition**

```sh
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 1GiB 100%

mkfs.vfat -F32 /dev/nvme0n1p1
```

**2. Create the ZFS pool and its datasets**

The command below creates Sparkle's encrypted layout. For Sparxie's intended unencrypted layout, omit `encryption`, `keylocation` and `keyformat` before running it.

For a mirrored data vdev, replace the final device with `mirror /dev/disk/by-id/<disk1>-part2 /dev/disk/by-id/<disk2>-part2`, after partitioning both disks. This only mirrors the ZFS vdev, not the EFI partition.

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

`services.zfs.autoSnapshot` (`modules/nixos/zfs.nix`) requires dataset opt-in, which can also be inherited. Mark the host's data datasets:

```sh
zfs set com.sun:auto-snapshot=true <hostname>/persist <hostname>/home
```

Each host also needs a unique `networking.hostId`; generate a candidate with `head -c4 /dev/urandom | od -An -tx4 | tr -d ' '` and check it against the other systems' IDs, including the vault guest's. The separate `vault` pool is handled inside that guest; see step 9.

**3. Mount**

```sh
mount -t tmpfs -o size=2G,mode=755 none /mnt
mkdir -p /mnt/{boot,nix,persist,home}
mount -o umask=0077 /dev/nvme0n1p1 /mnt/boot
mount -t zfs -o zfsutil <hostname>/nix /mnt/nix
mount -t zfs -o zfsutil <hostname>/persist /mnt/persist
mount -t zfs -o zfsutil <hostname>/home /mnt/home
```

**4. Clone the repo and update the hardware identifiers**

```sh
git clone <repo> /mnt/persist/nix-config
cd /mnt/persist/nix-config
blkid /dev/nvme0n1p1
```

Replace the EFI filesystem UUID in `hosts/<hostname>/hardware-configuration.nix` with the newly generated value. The ZFS dataset names must match the pool created above, and `networking.hostId` in `hosts/<hostname>/default.nix` must be unique. Preserve the tmpfs root, `/persist`'s `neededForBoot`, mount options, and host-specific hardware settings. When replacing hardware, also review the NIC identities and PCI passthrough addresses.

**5. Prepare the SSH host key and secrets**

Restore the existing host key and its `.pub` file to `/mnt/persist/etc/ssh/` if a backup is available. Otherwise generate a new key:

```sh
mkdir -p /mnt/persist/etc/ssh
ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
```

For a new key, obtain its age recipient using the pinned tool:

```sh
nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . nixpkgs#ssh-to-age \
  -c ssh-to-age < /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub
```

Update `<hostname>_host` in `.sops.yaml`, then update the host secrets with an existing authorized decryption identity available to SOPS:

```sh
nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . nixpkgs#sops \
  -c sops updatekeys hosts/<hostname>/secrets.yaml
```

For sparkle, also update `consoleKey` in `flake.nix` to the new SSH public key and run `sops updatekeys` on every guest secrets file whose creation rule includes `sparkle_host`. The SSH public key and age recipient are derived from the same host key. A new recipient cannot decrypt existing ciphertext until an authorized identity updates its recipients. If no authorized identity remains, recreate the secret values and encrypt them for the new recipients before installing. Restoring the original host key does not require changing recipients.

Restore sparkle's guest state and SSH keys under `/mnt/persist/vms/`. For new guests, provision their keys and secret recipients as described in [guest operations](guests.md) before starting them; services also need their persisted data or first-time initialization. Keep the vault pool passphrase available independently of its encrypted guest secret.

Use single-line passwords and tokens in runtime SOPS templates, including the environment files and the Authelia and ejabberd YAML snippets. Also respect each consuming application's quoting and value format: Authelia's client secrets are inserted into single-quoted scalars, and ejabberd's passwords into indented block scalars.

Attic and Vaultwarden embed their database passwords in connection URLs, so use URL-safe passwords for those roles, for example `openssl rand -hex 32`. When rotating a database password, update both the application guest's secret and the matching secret in the PostgreSQL guest for roles defined there.

**6. Prepare Secure Boot signing keys before installation (sparkle only)**

Lanzaboote needs signing keys when the installer writes the bootloader. Restore the existing `/var/lib/sbctl` backup into `/mnt/persist/var/lib/sbctl`, or create a new set there:

```sh
install -d -m 700 /mnt/persist/var/lib/sbctl
mkdir -p /mnt/var/lib
mount --bind /mnt/persist/var/lib /mnt/var/lib

cat > /tmp/sbctl-install.yaml <<'EOF'
keydir: /mnt/persist/var/lib/sbctl/keys
guid: /mnt/persist/var/lib/sbctl/GUID
EOF
nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . nixpkgs#sbctl \
  -c sbctl --config /tmp/sbctl-install.yaml create-keys
```

Skip `create-keys` when restoring keys. The bind mount makes the same persisted keys available at the install target's `/var/lib/sbctl`, where Lanzaboote expects them. See [sbctl 0.18's configuration reference](https://github.com/Foxboron/sbctl/blob/0.18/docs/sbctl.conf.5.txt) for `keydir` and `guid`. Sparxie uses systemd-boot and skips this step.

**7. Install**

```sh
nixos-install --no-root-passwd --flake /mnt/persist/nix-config#<hostname>
chown -R 1000:100 /mnt/persist/nix-config
```

Root password login stays locked, and both hosts disable root SSH login. The checkout belongs to `carmilla:users` (UID 1000, GID 100), so the user can edit it and the signed auto-update service can fetch into it.

Before rebooting, leave the checkout, unmount the target, and export the pool cleanly so the next boot does not need a forced import:

```sh
cd /
umount -R /mnt
zpool export <hostname>
```

For newly generated signing keys, boot sparkle with Secure Boot enforcement disabled until the keys are enrolled. The encrypted pool created in step 2 still requires its interactive passphrase.

**8. Enroll and verify Secure Boot (sparkle only)**

For new keys, enter the firmware's Secure Boot Setup Mode, preserving its forbidden-signature database (`dbx`), and boot the installed system. Log in as `carmilla`; the commands below use `doas` for elevation. Check the signed boot entries and enroll the keys:

```sh
doas sbctl status
doas sbctl verify
doas sbctl enroll-keys --microsoft
```

If restored keys are already enrolled, skip enrollment. Enable Secure Boot enforcement in firmware and reboot; confirm `bootctl status` reports Secure Boot enabled (user or deployed mode). This does not change the encrypted pool's interactive unlock.

**9. Prepare Vault's separate data pool (sparkle only)**

The configuration passes a SAS HBA to the vault guest. Its `vault` pool is imported and mounted inside the guest, with no host filesystem declaration for it. Restore that pool independently of the host's Borg backup, which does not cover it.

For a new pool, provision its disk layout inside the guest and create the datasets `vault/carmilla`, `vault/misc`, `vault/misc/library` and `vault/torrents`.

The unlock service expects the encryption root `vault`; use a passphrase key matching the `vault-zfs-key` SOPS secret, and retain `keylocation=prompt` for recovery. The service supplies the secret file's location only when loading the key. Use `mountpoint=none` for the pool's root dataset and its children so the configured filesystem mounts manage their paths.

As root inside the vault guest, first check that all four paths below are separate ZFS mounts:

```sh
findmnt -t zfs
```

For freshly provisioned datasets, set all four mount-root owners explicitly:

```sh
chown carmilla:users /vault/carmilla /vault/misc /vault/misc/library
chown 3000:3000 /vault/torrents
```

The library dataset mounts at `/vault/misc/library`; changing its parent's owner does not change this mount's owner. NFS squashes the read-only misc and library exports to UID 1000/GID 100, and the writable torrents export to UID/GID 3000. Preserve restored ownership and ACLs; existing torrent content must also permit UID/GID 3000 to write. Samba's writable carmilla share forces `carmilla:users`; provision its Samba password separately when starting fresh.

Vault also enables automatic snapshots. Opt its data datasets in from inside the guest, and inspect the effective properties, including any inherited overrides:

```sh
zfs set com.sun:auto-snapshot=true vault/carmilla vault/misc vault/misc/library vault/torrents
zfs get -r all vault | grep 'com.sun:auto-snapshot'
```

These snapshots stay on the Vault pool. The host Borg jobs do not back up that pool.
