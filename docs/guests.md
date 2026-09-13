# Guest operations

Each entry in `hosts/sparkle/guest-registry.nix` becomes a NixOS configuration and
an autostarted guest in Sparkle's closure. `deps` orders guest startup; it does not
wait for the application inside a guest to become ready.

```sh
microvm -s <name>
systemctl restart microvm@<name>
```

The console authenticates root over VSOCK using Sparkle's SSH host key. A host
switch installs new runners; the auto-update service restarts changed running guests.

To add a guest:

1. Add a unique name and index (10–99) to the registry and create its directory
   under `hosts/sparkle/guests/`. The index sets the VSOCK CID and address suffix.
   Preserve existing indices: the two decimal digits are also used as a hexadecimal MAC suffix.
2. Add a proxied service to `guest-web.nix` and its access policy to
   `guests/proxy/vhosts.nix`. The endpoint generates DNS and both proxy-to-guest firewall rules.
3. Declare `microvmGuest.egress` beside the service. Add other inbound flows to
   `dmz-bridge.nix` and the guest input firewall. See [network access](network.md).
4. For NFS, add the guest to `nfsClients` in `guest-net.nix`, declare its mount, and
   add an export with the appropriate access mode in `guests/vault/default.nix`.
5. Provision its SSH host key under `/persist/vms/<name>/etc/ssh/`, add its age
   recipient to `.sops.yaml`, and encrypt its secrets for both that key and Sparkle's.
   Restore application state or complete its first-time setup before starting it.

The CI runner uses a writable store overlay. Do not run Nix GC in it: overlay
whiteouts can hide paths in the host store that the next guest generation needs.
Sparkle stops this guest at noon and recreates its store and Nix database together.
Attic refills the store on subsequent builds. The volume images are disposable and
excluded from Borg backups; guest state under `/persist/vms/` is retained.
