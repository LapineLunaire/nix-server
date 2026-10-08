# Secure Boot on Sparkle

Sparxie uses systemd-boot and skips this page.

## Installer signing keys

Run as root in Bash from the installer's checkout at `/mnt/persist/nix-config`.

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

Return to [installation](install-servers.md#4-install-and-export) or [recovery](recover-servers.md). Keep enforcement disabled until the signing keys are enrolled.

## Installed system enrollment

If Sparkle's firmware does not have its keys enrolled, as with new keys or new hardware, enter Setup Mode in the firmware during a reboot while preserving `dbx`. After boot, run as `carmilla`:

```sh
doas sbctl status
doas sbctl verify
doas sbctl enroll-keys --microsoft
```

`sbctl verify` lists Lanzaboote's `kernel-*.efi` files under `EFI/nixos` as unsigned, which is expected. Enable Secure Boot in firmware, reboot, and confirm that `bootctl status` reports Secure Boot as `enabled (user)` or `enabled (deployed)`.
