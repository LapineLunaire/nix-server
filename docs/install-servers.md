# Install Sparkle or Sparxie

Use a UEFI NixOS installer for the target architecture whose ZFS is not newer than the hosts' ZFS 2.4. On Sparkle, disable Secure Boot enforcement before booting unsigned installation media. Run commands as root in Bash. Replace every `<placeholder>`; the hostname is `sparkle` or `sparxie`.

For recovery of an existing installation, follow [server recovery](recover-servers.md).

## 1. Partition and create datasets

The examples use `/dev/nvme0n1`, so substitute the actual disk; for `/dev/sda`, the partitions are `/dev/sda1` and `/dev/sda2`. **Partitioning and formatting erase the selected disk.**

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

On replacement Sparkle hardware, check the kernel `march` in `hosts/sparkle/default.nix`, the guest PCI passthrough addresses, and `max_phys_bits` in the vault and homeassistant guests. After [restoring the host key](keys.md#restore-identity-and-state), update the NIC MAC addresses in the `network/ipmi0-mac`, `network/sfp0-mac`, and `network/sfp1-mac` values of `hosts/sparkle/secrets.yaml`. On a replacement Sparxie VPS, update `hosts/sparxie/wan-net.nix` and the interface name and gateways in `hosts/sparxie/default.nix`.

## 3. Prepare identity and signing keys

1. [Restore the host identity, secrets and guest state](keys.md#restore-identity-and-state).
2. On Sparkle, [restore or create Secure Boot keys and bind-mount persisted `/var/lib`](secure-boot.md#installer-signing-keys) before installation. Sparxie uses systemd-boot.

## 4. Install and export

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

Run `reboot`. Sparkle asks for the pool passphrase on every boot; keep that passphrase outside SOPS. After boot, [enroll and verify Sparkle Secure Boot](secure-boot.md#installed-system-enrollment) and [prepare the vault pool](vault.md). Sparxie needs no key enrollment.
