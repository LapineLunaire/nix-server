# Borg backup to the Hetzner Storage Box from a ZFS snapshot of <pool>/persist. Call as (outputs.lib.mkBorgBackup { pool = "sparxie"; startAt = "03:00"; }).
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
    # Placeholder. preHook exports the real URL as BORG_REPO, which borg uses instead. It must not begin with "/" or ".", since nixpkgs reads that as a local repo and would then add RequiresMountsFor, a ReadWritePaths entry, and a tmpfiles rule for it.
    repo = "unset";
    paths = ["/mnt/borg-snapshot"];
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.sops.secrets."borg-passphrase".path}";
    };
    environment.BORG_RSH = "ssh -i ${config.sops.secrets."borg-ssh-key".path} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${config.sops.secrets."borg-known-hosts".path}";
    compression = "auto,zstd";
    # Run a backup missed while the host was down at the next boot. The stamp this reads lives in /var/lib/systemd/timers, which host-base persists, so it survives the tmpfs root. The same option gives the timer network-online ordering, which nixpkgs gates on it together with the repo being remote.
    persistentTimer = true;
    inherit startAt;
    preHook = ''
      export BORG_REPO=$(< ${config.sops.secrets."borg-repo".path})
      # Unmount any snapshot left by an interrupted run: a mounted snapshot makes the destroy below fail, and the create then aborts on the leftover.
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

  # The unit runs under ProtectSystem = "strict", which leaves only the module's own ReadWritePaths writable. The snapshot mount needs /mnt on top of those.
  systemd.services."borgbackup-job-hetzner".serviceConfig = {
    ReadWritePaths = ["/mnt"];
  };
}
