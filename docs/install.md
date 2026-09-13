# Installation

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

For sparkle, also update every guest secrets file whose creation rule includes `sparkle_host`. A new recipient cannot decrypt existing ciphertext; if the old identity is unavailable, recreate the secret values and encrypt them for the new recipients before installing. Restoring the original host key does not require re-encryption.

Restore sparkle's guest state and SSH keys under `/mnt/persist/vms/`. For new guests, provision their keys and secret recipients as described in [guest operations](guests.md) before starting them; services also need their persisted data or first-time initialization. Keep the vault pool passphrase available independently of its encrypted guest secret.

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

Skip `create-keys` when restoring keys. The bind mount makes the same persisted keys available at the install target's `/var/lib/sbctl`, where Lanzaboote expects them. See [sbctl's configuration reference](https://github.com/Foxboron/sbctl/blob/master/docs/sbctl.conf.5.scd) for `keydir` and `guid`. sparxie uses systemd-boot and skips this step.

**7. Install**

```sh
nixos-install --flake /mnt/persist/nix-config#<hostname>
```

Before rebooting, leave the checkout, unmount the target, and export the pool cleanly so the next boot does not need a forced import:

```sh
cd /
umount -R /mnt
zpool export <hostname>
```

For newly generated signing keys, boot sparkle with Secure Boot enforcement disabled until the keys are enrolled. Its ZFS pool still requires the interactive passphrase.

**8. Enroll and verify Secure Boot (sparkle only)**

For new keys, enter the firmware's Secure Boot Setup Mode, preserving its forbidden-signature database (`dbx`), and boot the installed system. Check the signed boot entries and enroll the keys:

```sh
doas sbctl status
doas sbctl verify
doas sbctl enroll-keys --microsoft
```

If restored keys are already enrolled, skip enrollment. Enable Secure Boot enforcement in firmware and reboot; confirm `bootctl status` reports Secure Boot enabled in user mode. sparkle's ZFS pool continues to use the interactive passphrase.
