# sparkle's addressing on the DMZ, the segment every server sits on: sparkle itself, the router, and the block it numbers its guests in.
# One source for the host's bridge address, each guest's address and gateway, the coredns zones, and every nftables rule written over the segment.
{
  hostAddress = "10.28.33.1";
  # Also the guests' default gateway, since they sit on this segment as peers.
  gateway = "10.28.32.1";
  # An integer, because networking.interfaces.<n>.ipv4.addresses.prefixLength is typed ints.between 0 32. Sites interpolating it into an address toString it.
  prefixLength = 23;
  subnet = "10.28.32.0/23";
  # The block inside the segment sparkle numbers its guests in: 10.28.33.<index>. Every host here carries the /23 above, so this is a numbering convention. Another hypervisor carves out its own block the same way.
  guestPrefix = "10.28.33";
  # The bridge sfp0 and every guest tap are ports of. sparkle's address lives on the bridge.
  bridge = "dmz0";
  # Management network behind the router, carrying the management surfaces: routers, switches, IPMI, and the UniFi APs.
  management = "10.28.16.0/24";
}
