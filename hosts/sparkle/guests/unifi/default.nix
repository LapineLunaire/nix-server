{
  dmz,
  net,
  web,
  outputs,
  ...
}: {
  imports = [
    outputs.nixosModules.acme
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

  # Image pulls and AP firmware (port 80: some controller versions fetch firmware over plain HTTP from fw-download.ubnt.com, which is Cloudflare-fronted through a weighted CNAME with 60/300s TTLs and so cannot be pinned to an address).
  # ACME issuance for unifi.lunaire.moe goes through lego (modules/nixos/acme.nix), whose propagation check queries the zone's authoritative nameservers directly. Cloudflare's addresses for those move, so this flow names no destination. TCP as well as UDP, since a truncated answer falls back to it.
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
    # Advertised to UniFi devices as the inform address; the APs sit on the management network, routed to the VM's own DMZ address with nothing NAT'ing in between, and the forward chain in hosts/sparkle/dmz-bridge.nix admits their inform/adoption/service traffic across that hop.
    uosSystemIP = net.vmAddress.unifi;
    # No reverse proxy; serve the UI straight on 443 with the real cert installed into unifi-core (see unifi-core-cert below).
    ports.ui = 443;
    # The host forward chain source-scopes ingress (see hosts/sparkle/dmz-bridge.nix), so the module's firewall openers stay off.
    openFirewallUiPort = false;
    openFirewallServicePorts = false;
  };

  # unifi-core only accepts an RSA cert through its unifi-core.crt/.key files, so this one cert opts out of the ec384 default.
  security.acme.certs."unifi.${web.domain}" = {
    keyType = "rsa4096";
    reloadServices = ["unifi-core-cert.service"];
  };

  # unifi-core reads unifi-core.crt/.key on container start, so installing the cert and restarting the container picks it up.
  # Change detection hashes the source cert to skip restarting the container when nothing changed.
  # security.acme reloads this unit on renewal; wantedBy covers the boot case.
  systemd.services.unifi-core-cert = {
    description = "Install ACME cert into unifi-core";
    after = ["podman-unifi-os-server.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
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
