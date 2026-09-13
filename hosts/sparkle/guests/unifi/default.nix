{
  net,
  web,
  ...
}: {
  imports = [
    ../../../../modules/nixos/acme.nix
    ./sops.nix
  ];

  # This guest's own Cloudflare token, scoped to lunaire.moe.
  host.acmeEmail = "certs@lunaire.eu";
  host.dnsApiTokenSecret = "lunaire-moe-dns-api-token";

  microvm = {
    vcpu = 4;
    mem = 6144;
    initialBalloonMem = 2048;
    # Dedicated XFS volume for podman; overlayfs can't run on virtiofs.
    volumes = [
      {
        image = "/persist/vms/unifi/volumes/podman.img";
        size = 10240;
        mountPoint = "/var/lib/containers";
        fsType = "xfs";
      }
    ];
  };

  # Allow image pulls, firmware downloads and DNS-01 propagation checks.
  microvmGuest.egress = [
    {
      proto = "tcp";
      ports = [80 443];
    }
    {
      proto = "udp";
      ports = [53];
    }
    {
      proto = "tcp";
      ports = [53];
    }
  ];

  virtualisation.podman.enable = true;

  services.unifi-os-server = {
    enable = true;
    # Advertise the guest address to APs on the management network.
    uosSystemIP = net.vmAddress.unifi;
    # Serve HTTPS directly with the certificate installed below.
    ports.ui = 443;
    # The host bridge firewall controls access to the container's published ports.
    openFirewallUiPort = false;
    openFirewallServicePorts = false;
  };

  # Use RSA for compatibility with unifi-core.
  security.acme.certs."unifi.${web.domain}" = {
    keyType = "rsa4096";
    reloadServices = ["unifi-core-cert.service"];
  };

  # Install renewed certificates and restart the container only when the certificate changes.
  systemd.services.unifi-core-cert = {
    description = "Install ACME cert into unifi-core";
    after = ["podman-unifi-os-server.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      # ACME uses try-reload-or-restart, which skips inactive units.
      RemainAfterExit = true;
    };
    script = ''
      src=/var/lib/acme/unifi.${web.domain}
      dst=/var/lib/unifi-os-server/data/unifi-core/config
      stamp=/var/lib/unifi-os-server/acme-imported.sum
      [ -f "$src/fullchain.pem" ] || exit 0
      sum=$(sha256sum "$src/fullchain.pem" | cut -d' ' -f1)
      [ "$sum" = "$(cat "$stamp" 2>/dev/null)" ] && exit 0
      install -Dm640 "$src/fullchain.pem" "$dst/unifi-core.crt"
      install -Dm640 "$src/key.pem" "$dst/unifi-core.key"
      systemctl restart podman-unifi-os-server.service
      echo "$sum" > "$stamp"
    '';
  };
}
