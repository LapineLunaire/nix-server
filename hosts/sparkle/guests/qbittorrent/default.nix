{
  config,
  dmz,
  net,
  web,
  lib,
  pkgs,
  ...
}: let
  # The port ProtonVPN forwards to this WireGuard config: opened on the confinement namespace and announced by qbittorrent as its listen port.
  forwardedPort = 57140;
in {
  imports = [./sops.nix];

  microvm = {
    vcpu = 2;
    mem = 1024;
    initialBalloonMem = 256;
  };

  # The torrents dataset, read-write over NFSv4. qBittorrent records absolute save paths in its resume data, so this path is fixed and DefaultSavePath below names it.
  # Mounted in this guest's root netns while qbittorrent runs inside qbtvpn. The NFS client does its RPC in the netns recorded at mount time, so storage leaves over eth0 while torrent traffic stays in the tunnel, and dmz-bridge.nix is what admits that flow.
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

  # The ProtonVPN endpoint. Torrent traffic stays inside the confinement namespace and never appears here. Confirm the port against the endpoint line in the sops-held wireguardConfigFile before trusting this.
  # The tunnel is carried by a wireguard interface created here and moved into the namespace, so its socket stays in this netns and the handshake leaves over the segment as ordinary udp.
  # The echo-request is the namespace's own precondition: vpn-confinement pings the endpoint from this netns before it will configure the tunnel, and exits non-zero after five failures, which takes qbittorrent down with it through bindsTo. The endpoint address lives only in the sops-held config, so this flow names no destination.
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
        # Placeholder in the store-rendered config; the ExecStartPre below swaps it for the sops-held hash after the module installs the file.
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

  # Runs after the module's ExecStartPre installs the rendered config (mkAfter), as the qbittorrent user like the rest of the unit.
  systemd.services.qbittorrent.serviceConfig.ExecStartPre = lib.mkAfter [
    "${pkgs.replace-secret}/bin/replace-secret '@WEBUI_PASSWORD_PBKDF2@' ${config.sops.secrets."qbittorrent-admin-password-hash".path} /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf"
  ];
}
