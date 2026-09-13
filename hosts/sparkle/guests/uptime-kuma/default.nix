{
  net,
  web,
  ...
}: {
  microvm = {
    vcpu = 2;
    mem = 1024;
    initialBalloonMem = 256;
  };

  # Monitors are configured at runtime and may use any port.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
    # The Nox / Carmilla site-to-site VPN link.
    {
      proto = "icmp";
      destinations = ["10.69.69.69"];
    }
  ];

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = net.vmAddress.uptime-kuma;
      PORT = toString web.endpoints.uptime-kuma.port;
    };
  };
}
