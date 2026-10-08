# SSH identity and secrets

## Restore identity and state

Run these steps as root in Bash from the installer's checkout at `/mnt/persist/nix-config`.

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

Return to [installation](install-servers.md#3-prepare-identity-and-signing-keys) or [server recovery](recover-servers.md). On an installed host, the `sops` shell alias derives the age identity from the SSH host key through doas; that alias is unavailable in the installer.
