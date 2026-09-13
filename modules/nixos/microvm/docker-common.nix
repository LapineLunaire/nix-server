{...}: {
  virtualisation.docker = {
    enable = true;
    daemon.settings.log-driver = "journald";

    # Reclaim superseded pinned images as well as dangling ones.
    # Running containers' images are kept; volumes are untouched (no --volumes), so bind-mounted state is safe.
    autoPrune = {
      enable = true;
      flags = ["--all"];
    };
  };
  virtualisation.oci-containers.backend = "docker";
}
