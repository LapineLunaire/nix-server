# Vault pool setup and recovery

Run these commands in the vault guest's root console.

## Set up or restore datasets

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
zfs set com.sun:auto-snapshot=true vault/carmilla vault/misc vault/torrents
zfs get -r com.sun:auto-snapshot vault
```

`vault/misc/library` inherits the snapshot property from `vault/misc` unless it has a local override. The recursive check shows the property value and source for each dataset.

Read-only NFS exports squash to UID 1000 and GID 100. The writable torrents export squashes to 3000:3000, so existing torrent content must be writable by that ID. Samba forces `carmilla:users` on the `carmilla` and `misc` shares; the read-only `torrents` share uses the authenticated user's permissions, so `carmilla` needs read access to the torrent content. For a fresh Samba account, run `smbpasswd -a carmilla` in the vault guest's root console. Snapshots stay on this pool.

## Recovery

If the vault guest cannot import or unlock its pool automatically, for example because its SOPS key is lost, import and unlock it from the guest's root console. Skip `zpool import` if `zpool list vault` already shows the pool:

```sh
zpool import -N vault
zfs load-key vault
systemctl restart vault-unlock
systemctl start nfs-server samba-smbd
```

If another machine still has a pool imported, shut it down or export the pool there before importing. Verify guest mounts and application state before resuming use.
