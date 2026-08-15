{
  config,
  outputs,
  pkgs,
  ...
}: let
  wan = import ./wan-net.nix;
in {
  imports = [
    outputs.nixosModules.host-base
    outputs.nixosModules.ip-whitelist
    outputs.nixosModules.zfs
    ./hardware-configuration.nix
    ./sops.nix
    ./services
  ];

  networking = {
    hostName = "sparxie";
    hostId = "33dd4911";
  };

  host.flakePath = "/persist/nix-config";

  # ACME account email and the sops secret holding the Cloudflare DNS-01 token, read by modules/nixos/caddy.nix.
  host.acmeEmail = "certs@lunaire.eu";
  host.dnsApiTokenSecret = "bunny-enterprises-dns-api-token";

  # sshd accepts connections only from the external addresses in these secrets. Nothing is exempt, since the veto chain runs ahead of the firewall's own loopback accept. A stale whitelist is recovered through the Hetzner console.
  ipWhitelist.ssh = {
    ports = [22];
    ipv4File = config.sops.secrets."ssh-allowed-ips-v4".path;
    ipv6File = config.sops.secrets."ssh-allowed-ips-v6".path;
  };

  # Static network config per Hetzner VPS requirements (https://docs.hetzner.com/cloud/servers/static-configuration/).
  # The IPv4 gateway is off-subnet relative to the /32 address, so the route needs GatewayOnLink. The IPv6 default gateway is the router's link-local address.
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
    # Explicit zfs major version pin, upgraded deliberately in lockstep with the kernel pin above.
    zfs.package = pkgs.zfs_2_4;
  };

  system.stateVersion = "26.05";
  home-manager.users.carmilla.home.stateVersion = "26.05";
}
