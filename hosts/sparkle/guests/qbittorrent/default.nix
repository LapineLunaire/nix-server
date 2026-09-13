{
  config,
  net,
  web,
  lib,
  pkgs,
  ...
}: let
  # Match the port forwarded by this ProtonVPN configuration.
  forwardedPort = 57140;
in {
  imports = [./sops.nix];

  microvm = {
    vcpu = 2;
    mem = 1024;
    initialBalloonMem = 256;
  };

  # Keep qBittorrent's recorded save paths. NFS uses the guest network; torrents use qbtvpn.
  fileSystems."/mnt/samba/torrents" = {
    device = "${net.vmAddress.vault}:/vault/torrents";
    fsType = "nfs4";
    options = [
      "_netdev"
      "x-systemd.automount"
      "x-systemd.mount-timeout=20"
      "x-systemd.idle-timeout=600"
      "noatime"
    ];
  };

  # WireGuard handshakes leave from this namespace. vpn-confinement also pings the endpoint.
  # The endpoint address is held in SOPS; verify its port when replacing the VPN configuration.
  microvmGuest.egress = [
    {
      proto = "udp";
      ports = [51820];
    }
    {
      proto = "icmp";
    }
  ];

  vpnNamespaces.qbtvpn = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."qbittorrent-protonvpn-conf".path;
    accessibleFrom = ["${net.vmAddress.proxy}/32"];
    portMappings = [
      {
        from = web.endpoints.qbittorrent.port;
        to = web.endpoints.qbittorrent.port;
        protocol = "tcp";
      }
    ];
    openVPNPorts = [
      {
        port = forwardedPort;
        protocol = "both";
      }
    ];
  };

  services.qbittorrent = {
    enable = true;
    openFirewall = false;
    webuiPort = web.endpoints.qbittorrent.port;
    torrentingPort = forwardedPort;
    serverConfig = {
      Core.AutoDeleteAddedTorrentFile = "Never";
      Preferences.WebUI = {
        LocalHostAuth = true;
        # Replace the placeholder after the module installs the configuration.
        Password_PBKDF2 = "@WEBUI_PASSWORD_PBKDF2@";
      };
      BitTorrent.Session = {
        DefaultSavePath = "/mnt/samba/torrents";
        TempPath = "/mnt/samba/torrents/incomplete";
        TempPathEnabled = true;
        AnonymousModeEnabled = true;
        GlobalMaxSeedingMinutes = -1;
        MaxActiveTorrents = -1;
        MaxActiveDownloads = 8;
        MaxActiveUploads = -1;
      };
    };
  };

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "qbtvpn";
  };

  # Run as qBittorrent after its generated ExecStartPre installs the configuration.
  systemd.services.qbittorrent.serviceConfig.ExecStartPre = lib.mkAfter [
    "${pkgs.replace-secret}/bin/replace-secret '@WEBUI_PASSWORD_PBKDF2@' ${config.sops.secrets."qbittorrent-admin-password-hash".path} /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf"
  ];
}
