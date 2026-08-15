# Shared Docker config for microVM guests that run Docker containers.
# Container stdout and stderr go to the journal, which keeps them off the small docker.img volume.
# /var/log is persisted to the host (see guest.nix), so logs survive reboots and stay off the volume; `journalctl CONTAINER_NAME=<name>` and `docker logs` both read them back.
{...}: {
  virtualisation.docker = {
    enable = true;
    daemon.settings.log-driver = "journald";

    # Weekly `docker system prune`. --all also reclaims superseded images: refs are pinned by digest, so a bumped digest (via the container-update workflow) leaves the old image unused-but-tagged, which a plain dangling-only prune never removes.
    # Running containers' images are kept; volumes are untouched (no --volumes), so bind-mounted state is safe.
    autoPrune = {
      enable = true;
      flags = ["--all"];
    };
  };
  virtualisation.oci-containers.backend = "docker";
}
