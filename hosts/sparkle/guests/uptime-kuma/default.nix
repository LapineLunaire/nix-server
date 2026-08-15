{
  net,
  web,
  ...
}: let
in {
  microvm = {
    vcpu = 2;
    mem = 1024;
    initialBalloonMem = 256;
  };

  # Monitors and notification channels live in this guest's database, not here: a port monitor can target any port and a ping monitor needs ICMP. Narrowing this would break checks silently, so it keeps the reach it has today.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = net.vmAddress.uptime-kuma;
      PORT = toString web.endpoints.uptime-kuma.port;
    };
  };
}
