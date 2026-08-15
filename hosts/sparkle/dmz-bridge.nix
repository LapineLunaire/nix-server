# The dmz0 bridge sparkle shares with the rest of the DMZ: sfp0 and every guest tap are ports of it, sparkle's own address lives on it, and the default-drop forward chain over it carries one rule per allowed flow.
# Both sides of a rule name bridge ports, "sfp0" for the segment and the guest's own name for its tap, which identity.nix sets. That is why this is a bridge-family table: it is the only family whose forward hook sees the ports at all.
{
  config,
  lib,
  outputs,
  ...
}: let
  # The trusted client subnets sparkle admits here. From trusted-subnets.nix, the same list the proxy guest applies as its vhost ACLs.
  trusted = config.host.trustedSubnetsNft;
  trustedSubnets = import ./trusted-subnets.nix;
  # The LAN and the router, the only two sources a discovery probe for the vault guest can arrive from. The vault guest derives the same pair and mirrors these rules on its own input chain.
  discoverySources = "${trustedSubnets.lan}, ${dmz.gateway}";
  dmz = import ./dmz-net.nix;
  net = import ./guest-net.nix;
  registry = import ./guest-registry.nix;
  web = import ./guest-web.nix;
  guests = net.tapsNft;
  # Private space, excluded from any flow that names no destination of its own.
  privateSpace = "{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 }";
  # One accept per declared flow. A flow naming no destination keeps the private-space exclusion, which confines it to addresses outside the LAN and the management network.
  renderFlow = tap: flow: let
    destination =
      if flow.destinations == []
      then "ip daddr != ${privateSpace}"
      else "ip daddr { ${lib.concatStringsSep ", " flow.destinations} }";
    portSet = dir: list: lib.optionalString (flow.proto != "icmp" && list != []) " ${flow.proto} ${dir} { ${lib.concatMapStringsSep ", " toString list} }";
    sports = portSet "sport" flow.sourcePorts;
    ports = portSet "dport" flow.ports;
    # A sport or dport match carries the protocol itself, so meta l4proto is only needed when the flow names neither.
    match =
      if flow.proto == "icmp"
      then " icmp type echo-request"
      else lib.optionalString (flow.ports == [] && flow.sourcePorts == []) " meta l4proto ${flow.proto}";
  in "iifname \"${tap}\" oifname \"sfp0\" ${destination}${match}${sports}${ports} accept";
  # Read back from each guest's own evaluated config, since the host already evaluates every guest for microvm.vms, so a guest's outbound needs stay declared next to the service that has them.
  egressRules = lib.concatStringsSep "\n" (lib.concatLists (lib.mapAttrsToList (name: _:
    map (renderFlow name) outputs.nixosConfigurations.${name}.config.microvmGuest.egress)
  registry));
in {
  # Conntrack for bridged frames, read by the ct rules below. Loading br_netfilter would hand the inet forward chain the bridge master as both iifname and oifname, collapsing the port information these rules match on.
  boot.kernelModules = ["nf_conntrack_bridge"];

  # sparkle uses systemd-networkd exclusively, so the bridge is declared as a netdev here.
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

  # Routed traffic, which is separate from the segment policy below. Nothing on this host routes, so the chain is left at its default-drop policy.
  networking.firewall.filterForward = true;

  # Default-drop over the bridge: nothing crosses between a guest tap and the segment, or between two guest taps, without a rule here. Frames to and from sparkle's own address take the bridge's input and output hooks instead, so this chain never sees them and the host's own reachability is the inet table's business.
  networking.nftables.tables.dmz = {
    family = "bridge";
    content = ''
      chain forward {
        type filter hook forward priority filter; policy drop;

        # Neighbour resolution across the segment, which carries none of the addresses or ports the rules below match on.
        ether type arp accept

        ct state invalid drop
        ct state established,related accept

        # LAN and VPN: git-over-ssh to forgejo, and ICMP to any guest.
        iifname "sfp0" oifname "forgejo" ip saddr { ${trusted} } tcp dport 22 accept
        iifname "sfp0" oifname { ${guests} } ip saddr { ${trusted} } icmp type echo-request accept

        # monitoring: scrape node_exporter on every guest.
        iifname "monitoring" oifname { ${guests} } tcp dport ${toString net.nodeExporterPort} accept

        # PostgreSQL, from the client guests listed in guest-net.nix.
        iifname { ${guests} } oifname "postgres" tcp dport ${toString net.postgresPort} ip saddr { ${net.postgresClientsNft} } accept

        # NFSv4 to the vault guest from the clients listed in guest-net.nix. v4-only, so 2049 is the whole surface.
        iifname { ${guests} } oifname "vault" tcp dport ${toString net.nfsPort} ip saddr { ${net.nfsClientsNft} } accept

        # SMB from the trusted client subnets, which is where every SMB client is: the guests read the vault over NFS, so no guest and not sparkle appears here.
        iifname "sfp0" oifname "vault" ip saddr { ${trusted} } tcp dport { 139, 445 } accept
        # Discovery: NetBIOS and the wsdd HTTP endpoint, from those same clients plus the router, whose repeater re-emits their multicast with its own address.
        iifname "sfp0" oifname "vault" ip saddr { ${discoverySources} } udp dport { 137, 138 } accept
        iifname "sfp0" oifname "vault" ip saddr { ${discoverySources} } tcp dport 5357 accept
        # mDNS and WS-Discovery, matched on the destination group: the router's repeater re-emits with its own address, so source-scoping would drop what the LAN clients rely on.
        iifname "sfp0" oifname "vault" ip daddr 224.0.0.251 udp dport 5353 accept
        iifname "sfp0" oifname "vault" ip daddr 239.255.255.250 udp dport 3702 accept

        # The resolver for the whole network: every guest and every client on the segment reaches it, unfiltered by source.
        iifname { ${guests} } oifname "dns" udp dport 53 accept
        iifname { ${guests} } oifname "dns" tcp dport 53 accept
        iifname "sfp0" oifname "dns" udp dport 53 accept
        iifname "sfp0" oifname "dns" tcp dport 53 accept

        # Clients reach the proxy; each vhost's own source-IP allowlist gates the rest.
        iifname "sfp0" oifname "proxy" ip saddr { ${trusted}, ${dmz.subnet} } tcp dport { 80, 443 } accept
        # Guests that call a vhost: uptime-kuma probes.
        iifname { "uptime-kuma", "forgejo", "pgadmin" } oifname "proxy" tcp dport 443 accept
        # The proxy reaches each backend on the port guest-web.nix gives it.
        ${lib.concatStrings (lib.mapAttrsToList (name: e: "iifname \"proxy\" oifname \"${name}\" tcp dport ${toString e.port} accept\n") web.endpoints)}

        # Per-guest egress off the segment, declared by each guest. No blanket grant: a guest with nothing declared reaches nothing.
        ${egressRules}

        # Multicast from the vault tap floods to every port. The sfp0 copies are accepted above, and this drops the copies aimed at other taps, keeping them out of the log below.
        iifname "vault" ip daddr { 224.0.0.251, 239.255.255.250 } drop

        iifname { ${guests} } limit rate 10/second log prefix "guest-egress-drop "
      }
    '';
  };
}
