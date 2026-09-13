{
  hostAddress = "10.28.33.1";
  gateway = "10.28.32.1";
  prefixLength = 23;
  subnet = "10.28.32.0/23";
  # Number guests in 10.28.33.x within the shared /23.
  guestPrefix = "10.28.33";
  bridge = "dmz0";
  # Routers, switches, IPMI and UniFi APs.
  management = "10.28.16.0/24";
}
