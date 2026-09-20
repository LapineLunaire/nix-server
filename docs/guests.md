# Guest operations

Each entry in `hosts/sparkle/guest-registry.nix` becomes a NixOS configuration and an autostarted guest in Sparkle's closure. `deps` orders guest startup; it does not wait for the application inside a guest to become ready.

```sh
doas microvm -s <name>
doas systemctl restart microvm@<name>
```

The console authenticates root over VSOCK using Sparkle's SSH host key. A host switch installs new runners; the auto-update service restarts changed running guests. After a manual switch, restart the changed guests explicitly. Console access needs root because it reads the host private key.

To add a guest:

1. Add a unique name and index (10-99) to the registry and create its directory under `hosts/sparkle/guests/`. The index sets the VSOCK CID and address suffix. Preserve existing indices: the two decimal digits are also used as a hexadecimal MAC suffix.
2. For a proxied service, add its endpoint to `guest-web.nix` and its access policy to `guests/proxy/vhosts.nix`. The endpoint generates DNS and both proxy-to-guest firewall rules.
3. Declare `microvmGuest.egress` beside the service. Add other inbound flows to `dmz-bridge.nix` and the guest input firewall. See [network access](network.md).
4. For NFS, add the guest to `nfsClients` in `guest-net.nix`, declare its mount, and add an export with the appropriate access mode in `guests/vault/default.nix`.
5. Provision its SSH host key and public key under `/persist/vms/<name>/etc/ssh/` on Sparkle as `ssh_host_ed25519_key` and `ssh_host_ed25519_key.pub`; preserve existing keys when restoring a guest. For a new identity, run `ssh-keygen -t ed25519 -N "" -f /persist/vms/<name>/etc/ssh/ssh_host_ed25519_key` as root after creating the parent directory. If the guest uses SOPS secrets, add its age recipient and a matching creation rule to `.sops.yaml`, and encrypt its secrets for both that key and Sparkle's. Restore required application state before starting the guest; complete any application-specific initialization afterward.

Every guest uses a writable store overlay at `/nix/.rw-store`. Most keep it on the tmpfs root; the CI runner uses a persistent 128 GiB XFS volume and also persists `/nix/var`. Do not run Nix GC in the CI guest: overlay whiteouts can hide host-store paths needed by a later guest generation.

Sparkle stops this guest daily at 12:00 UTC, deletes its store image and Nix database, and starts it again so the store image is recreated. Missed resets are not caught up. Subsequent builds can refill it from configured caches, including Attic, or rebuild missing paths.

Borg excludes `/persist/vms/*/volumes/`, including the CI store, build scratch and swap images and the Home Assistant and UniFi container-storage images. State in the host's `persist` dataset outside those directories is included; the vault guest's separate ZFS pool is not. Sparkle creates image directories owned by `microvm:kvm` with mode `0750`. Preserve numeric owners when restoring guest state.
