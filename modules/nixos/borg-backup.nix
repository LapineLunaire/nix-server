{
  pool,
  startAt,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  job = config.services.borgbackup.jobs.hetzner;
  loadRepository = ''
    BORG_REPO=$(< ${config.sops.secrets."borg-repo".path})
    : "''${BORG_REPO:?Borg repository secret is empty}"
    export BORG_REPO
  '';
  lastSuccess = "/var/lib/borgbackup/hetzner/last-success";
in {
  imports = [./mail-relay.nix];

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
    # borg-job-hetzner replaces the upstream wrapper, which cannot read the repository secret.
    wrapper = null;
    # A wrong repository secret must fail rather than initialize a new repository.
    doInit = false;
    paths = ["/mnt/borg-snapshot"];
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.sops.secrets."borg-passphrase".path}";
    };
    environment.BORG_RSH = "ssh -i ${config.sops.secrets."borg-ssh-key".path} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${config.sops.secrets."borg-known-hosts".path}";
    compression = "auto,zstd";
    # Exclude disposable guest caches. sh: keeps * within one path component.
    exclude = [
      "sh:/mnt/borg-snapshot/vms/*/volumes"
      # A restored database must not advertise paths from the excluded writable store.
      "pp:/mnt/borg-snapshot/vms/ci-runner/nix/var"
    ];
    # Persist missed runs; /var/lib/systemd/timers survives the tmpfs root.
    persistentTimer = true;
    inherit startAt;
    preHook = ''
      ${loadRepository}
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
    # The script's last step, reached only after every Borg command succeeds.
    postPrune = ''
      ${pkgs.coreutils}/bin/touch ${lastSuccess}
    '';
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 3;
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "borg-job-hetzner" ''
      set -euo pipefail
      ${loadRepository}
      export BORG_PASSCOMMAND=${lib.escapeShellArg job.encryption.passCommand}
      export BORG_RSH=${lib.escapeShellArg job.environment.BORG_RSH}
      exec ${lib.getExe config.services.borgbackup.package} "$@"
    '')
  ];

  systemd.services."borgbackup-job-hetzner" = {
    onFailure = ["borgbackup-failed.service"];
    # Allow the snapshot mount and the success marker under ProtectSystem=strict.
    serviceConfig = {
      ReadWritePaths = ["/mnt"];
      StateDirectory = "borgbackup/hetzner";
    };
  };

  systemd.services.borgbackup-failed = {
    description = "Mail the failed Borg backup log";
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      {
        printf 'Subject: ${config.networking.hostName}: Borg backup failed\n\n'
        ${config.systemd.package}/bin/journalctl -u borgbackup-job-hetzner -n 50 --no-pager
      } | ${config.programs.msmtp.package}/bin/sendmail carmilla@lunaire.eu
    '';
  };

  # The failure hook cannot report a backup that never runs.
  systemd.services.borgbackup-freshness = {
    description = "Mail when no Borg backup succeeded in 24 hours";
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      if [[ -z "$(${pkgs.findutils}/bin/find ${lastSuccess} -mmin -1440 2>/dev/null)" ]]; then
        printf 'Subject: ${config.networking.hostName}: Borg backup overdue\n\nNo successful backup in the last 24 hours.\n' \
          | ${config.programs.msmtp.package}/bin/sendmail carmilla@lunaire.eu
      fi
    '';
  };

  # Run after the night's backup.
  systemd.timers.borgbackup-freshness = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "12:00";
      Persistent = true;
    };
  };
}
