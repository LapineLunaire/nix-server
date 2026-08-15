# The client networks trusted to reach the guests' admin surfaces, named individually because they are not all trusted with the same things. All four are reached across the router; none is adjacent on the DMZ.
# `all` gates the routed surfaces and lives here once, read by sparkle, the proxy guest, the vault guest, and the forgejo guest.
# `lan` is named separately because link-local discovery stays on its own segment. mDNS and WS-Discovery reach the guests from the one client network attached to the router that repeats them, so the vault guest scopes discovery to `lan`.
let
  lan = "10.28.64.0/24";
  vpn = "10.28.96.0/24";
  noxLan = "10.100.0.0/24";
  noxVpn = "10.1.0.0/24";
in {
  inherit lan vpn noxLan noxVpn;
  all = [lan vpn noxLan noxVpn];
}
