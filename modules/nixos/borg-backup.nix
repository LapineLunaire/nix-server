{
  pool,
  startAt,
}: {
  config,
  pkgs,
  ...
}: {
  sops.secrets = {
    "borg-passphrase" = {};
    "borg-ssh-key" = {};
    "borg-repo" = {};
    # Full known_hosts line for the storage box, obtained with: ssh-keyscan -p 23 <hostname>
    "borg-known-hosts" = {};
  };

  services.borgbackup.jobs.hetzner = {
    # BORG_REPO supplies the runtime URL. A non-path placeholder avoids local-repository setup.
    repo = "unset";
    paths = ["/mnt/borg-snapshot"];
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.sops.secrets."borg-passphrase".path}";
    };
    environment.BORG_RSH = "ssh -i ${config.sops.secrets."borg-ssh-key".path} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${config.sops.secrets."borg-known-hosts".path}";
    compression = "auto,zstd";
    # Exclude disposable guest caches. sh: keeps * within one path component.
    exclude = ["sh:/mnt/borg-snapshot/vms/*/volumes"];
    # Persist missed runs; /var/lib/systemd/timers survives the tmpfs root.
    persistentTimer = true;
    inherit startAt;
    preHook = ''
      export BORG_REPO=$(< ${config.sops.secrets."borg-repo".path})
      # Recover the mount and snapshot left by an interrupted backup.
      ${pkgs.util-linux}/bin/umount /mnt/borg-snapshot 2>/dev/null || true
      ${pkgs.zfs}/bin/zfs destroy ${pool}/persist@borg-backup 2>/dev/null || true
      ${pkgs.zfs}/bin/zfs snapshot ${pool}/persist@borg-backup
      ${pkgs.coreutils}/bin/mkdir -p /mnt/borg-snapshot
      ${pkgs.util-linux}/bin/mount -t zfs ${pool}/persist@borg-backup /mnt/borg-snapshot
    '';
    postHook = ''
      ${pkgs.util-linux}/bin/umount /mnt/borg-snapshot 2>/dev/null || true
      ${pkgs.zfs}/bin/zfs destroy ${pool}/persist@borg-backup 2>/dev/null || true
    '';
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 3;
    };
  };

  # Allow the snapshot mount under ProtectSystem=strict.
  systemd.services."borgbackup-job-hetzner".serviceConfig = {
    ReadWritePaths = ["/mnt"];
  };
}
