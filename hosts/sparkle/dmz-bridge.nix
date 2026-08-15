# The dmz0 bridge sparkle shares with the rest of the DMZ: sfp0 and every guest tap are ports of it, and sparkle's own address lives on it rather than on sfp0.
{...}: let
  dmz = import ./dmz-net.nix;
in {
  # Conntrack for bridged frames, read by the ct rules in the segment policy. br_netfilter is deliberately absent: it hands the inet forward chain the bridge master as both iifname and oifname, so a rule there could never name the port a frame crossed.
  boot.kernelModules = ["nf_conntrack_bridge"];

  # sparkle uses systemd-networkd exclusively. Do not use networking.bridges, which is scripted networking, alongside it.
  systemd.network.netdevs."10-${dmz.bridge}" = {
    netdevConfig = {
      Kind = "bridge";
      Name = dmz.bridge;
    };
  };
  systemd.network.networks."10-${dmz.bridge}" = {
    matchConfig.Name = dmz.bridge;
    networkConfig = {
      Address = "${dmz.hostAddress}/${toString dmz.prefixLength}";
      Gateway = dmz.gateway;
      ConfigureWithoutCarrier = true;
    };
  };

  # Routed traffic, which is separate from the segment policy over the bridge. Nothing on this host routes, so the chain is left at its default-drop policy.
  networking.firewall.filterForward = true;
}
