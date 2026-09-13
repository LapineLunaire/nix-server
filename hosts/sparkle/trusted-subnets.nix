let
  lan = "10.28.64.0/24";
  vpn = "10.28.96.0/24";
  noxLan = "10.100.0.0/24";
  noxVpn = "10.1.0.0/24";
in {
  inherit lan vpn noxLan noxVpn;
  all = [lan vpn noxLan noxVpn];
}
