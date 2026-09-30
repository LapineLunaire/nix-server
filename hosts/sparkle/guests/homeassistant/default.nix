{
  microvm = {
    vcpu = 2;
    mem = 2048;
    initialBalloonMem = 512;
    # Limit guest addresses to the 39-bit VT-d aperture; higher PCI BARs fail IOMMU mapping.
    cloud-hypervisor.extraArgs = ["--cpus" "max_phys_bits=39"];
    volumes = [
      {
        image = "/persist/vms/homeassistant/volumes/docker.img";
        mountPoint = "/var/lib/docker";
        size = 10240;
        fsType = "xfs";
      }
    ];
    devices = [
      {
        bus = "pci";
        # Pass the Zigbee stick's USB controller through to the guest.
        path = "0000:00:14.0";
      }
    ];
  };

  # Runtime integrations may use ports beyond HTTPS, such as MQTT on 8883.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  virtualisation.docker = {
    enable = true;
    daemon.settings.log-driver = "journald";
    # Also remove superseded pinned images; volumes are untouched.
    autoPrune = {
      enable = true;
      flags = ["--all"];
    };
  };
  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers.homeassistant = {
    image = "ghcr.io/home-assistant/home-assistant@sha256:3e6710a7ab2a61311d9d899b719f6c3657791c63e8f4942cec4ebc42401d6b76";
    autoStart = true;
    volumes = ["/persist/var/lib/hass:/config"];
    environment.TZ = "Etc/UTC";
    extraOptions = [
      "--device=/dev/ttyUSB0:/dev/ttyUSB0"
      "--network=host"
    ];
  };
}
