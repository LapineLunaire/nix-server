{pkgs, ...}: let
  wan = import ./wan-net.nix;
in {
  imports = [
    ../../modules/nixos/host-base
    # Recover a stale SSH allowlist through the Hetzner console.
    ../../modules/nixos/ssh-ip-whitelist.nix
    ../../modules/nixos/zfs.nix
    ./hardware-configuration.nix
    ./sops.nix
    ./services
    ./auto-update.nix
  ];

  networking = {
    hostName = "sparxie";
    hostId = "33dd4911";
  };

  host.flakePath = "/persist/nix-config";

  host.acmeEmail = "certs@lunaire.eu";
  host.dnsApiTokenSecret = "bunny-enterprises-dns-api-token";

  # Sparxie listens; the proxy guest connects to it.
  host.wireguardTunnel = {
    prefixLength = "31";
    listenPort = wan.wireguardPort;
    local.ip = "10.73.212.1";
    peer = {
      ip = "10.73.212.0";
      publicKey = "fU36EC/ymy4d1XwJCfqAXKEX8dRK/WuMFBbh6OtKBRM=";
    };
  };

  # Hetzner's IPv4 gateway is outside the /32, so it needs GatewayOnLink.
  systemd.network.networks."30-wan" = {
    matchConfig.Name = "enp1s0";
    networkConfig.DHCP = "no";
    address = [
      "${wan.ipv4}/32"
      "${wan.ipv6}/64"
    ];
    routes = [
      {
        Gateway = "172.31.1.1";
        GatewayOnLink = true;
      }
      {Gateway = "fe80::1";}
    ];
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_6_18;
    # Update ZFS and the kernel together.
    zfs.package = pkgs.zfs_2_4;
  };

  system.stateVersion = "26.05";
  home-manager.users.carmilla.home.stateVersion = "26.05";
}
