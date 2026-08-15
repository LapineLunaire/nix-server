{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."qbittorrent-protonvpn-conf" = {};
    # Read by the unprivileged ExecStartPre in default.nix that splices it into qBittorrent.conf.
    secrets."qbittorrent-admin-password-hash" = {
      owner = "qbittorrent";
      restartUnits = ["qbittorrent.service"];
    };
  };
}
