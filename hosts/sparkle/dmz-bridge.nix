{
  config,
  lib,
  guestConfigurations,
  ...
}: let
  dmz = import ./dmz-net.nix;
in {
  # Use bridge conntrack. br_netfilter hides the tap names these rules need.
  boot.kernelModules = ["nf_conntrack_bridge"];

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

  # Drop routed forwarding; guest traffic uses the bridge rules below.
  networking.firewall.filterForward = true;

  # Filter traffic between taps and sfp0. Traffic to Sparkle itself uses its input firewall.
  networking.nftables.tables.dmz = let
    trusted = config.host.trustedSubnetsNft;
    trustedSubnets = import ./trusted-subnets.nix;
    # Include the router that repeats LAN discovery.
    discoverySources = "${trustedSubnets.lan}, ${dmz.gateway}";
    net = import ./guest-net.nix;
    registry = import ./guest-registry.nix;
    web = import ./guest-web.nix;
    guests = net.tapsNft;
    # Read each MAC from the guest configuration.
    guestMacsNft = lib.concatStringsSep ", " (lib.mapAttrsToList (name: _: "\"${name}\" . ${(builtins.head guestConfigurations.${name}.config.microvm.interfaces).mac}") registry);
    # Private space, excluded from any flow that names no destination of its own.
    privateSpace = "{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 }";
    # Unspecified destinations exclude private networks.
    renderFlow = tap: flow: let
      destination =
        if flow.destinations == []
        then "ip daddr != ${privateSpace}"
        else "ip daddr { ${lib.concatStringsSep ", " flow.destinations} }";
      portSet = dir: list: lib.optionalString (flow.proto != "icmp" && list != []) " ${flow.proto} ${dir} { ${lib.concatMapStringsSep ", " toString list} }";
      sports = portSet "sport" flow.sourcePorts;
      ports = portSet "dport" flow.ports;
      # Port matches imply the protocol; unbounded flows need an explicit match.
      match =
        if flow.proto == "icmp"
        then " icmp type echo-request"
        else lib.optionalString (flow.ports == [] && flow.sourcePorts == []) " meta l4proto ${flow.proto}";
    in "iifname \"${tap}\" oifname \"sfp0\" ${destination}${match}${sports}${ports} accept";
    # Read outbound allowances from each service's guest configuration.
    egressRules = lib.concatStringsSep "\n" (lib.concatLists (lib.mapAttrsToList (name: _:
      map (renderFlow name) guestConfigurations.${name}.config.microvmGuest.egress)
    registry));
  in {
    family = "bridge";
    content = ''
      set guest-identity {
        type ifname . ipv4_addr
        elements = { ${net.guestIdentityNft} }
      }

      set guest-mac {
        type ifname . ether_addr
        elements = { ${guestMacsNft} }
      }

      # Reject spoofed sources before bridge conntrack (-200) sees them.
      chain antispoof {
        type filter hook prerouting priority -300; policy accept;

        iifname != { ${guests} } accept

        # Validate before MAC learning, so a guest cannot move another guest's bridge entry.
        iifname . ether saddr != @guest-mac goto spoof-drop

        ether type ip iifname . ip saddr != @guest-identity goto spoof-drop
        # Check the ARP payload as well as the Ethernet source.
        ether type arp iifname . arp saddr ip != @guest-identity goto spoof-drop
      }

      # Log only rejected frames, with a rate limit.
      chain spoof-drop {
        limit rate 10/second log prefix "guest-spoof-drop "
        drop
      }

      chain forward {
        type filter hook forward priority filter; policy drop;

        # Allow ARP after validating guest identities.
        ether type arp accept

        ct state invalid drop
        ct state established,related accept

        # LAN and VPN: git-over-ssh to forgejo, and ICMP to any guest.
        iifname "sfp0" oifname "forgejo" ip saddr { ${trusted} } tcp dport 22 accept
        iifname "sfp0" oifname { ${guests} } ip saddr { ${trusted} } icmp type echo-request accept

        # Uptime Kuma checks Forgejo's Git-over-SSH service.
        iifname "uptime-kuma" oifname "forgejo" tcp dport 22 accept

        # monitoring: scrape node_exporter on every guest.
        iifname "monitoring" oifname { ${guests} } tcp dport ${toString net.nodeExporterPort} accept

        # PostgreSQL, from the client guests listed in guest-net.nix.
        iifname { ${guests} } oifname "postgres" tcp dport ${toString net.postgresPort} ip saddr { ${net.postgresClientsNft} } accept

        # NFSv4 to the vault guest from the clients listed in guest-net.nix. v4-only, so 2049 is the whole surface.
        iifname { ${guests} } oifname "vault" tcp dport ${toString net.nfsPort} ip saddr { ${net.nfsClientsNft} } accept

        # SMB is for trusted clients; guests use NFS.
        iifname "sfp0" oifname "vault" ip saddr { ${trusted} } tcp dport { 139, 445 } accept
        # NetBIOS and wsdd discovery from the LAN and its repeater.
        iifname "sfp0" oifname "vault" ip saddr { ${discoverySources} } udp dport { 137, 138 } accept
        iifname "sfp0" oifname "vault" ip saddr { ${discoverySources} } tcp dport 5357 accept
        # Match multicast destinations; repeated discovery may have the router's source address.
        iifname "sfp0" oifname "vault" ip daddr 224.0.0.251 udp dport 5353 accept
        iifname "sfp0" oifname "vault" ip daddr 239.255.255.250 udp dport 3702 accept

        # UniFi controller reaches the APs on the management network for adoption, provisioning, and firmware pushes.
        iifname "unifi" oifname "sfp0" ip daddr ${dmz.management} accept
        # UniFi APs reach the controller for L3 inform and adoption and for service traffic.
        iifname "sfp0" oifname "unifi" ip saddr ${dmz.management} tcp dport { 8080, 8443, 6789, 8880, 8843 } accept
        iifname "sfp0" oifname "unifi" ip saddr ${dmz.management} udp dport { 3478, 10001 } accept
        # Admins reach the controller web UI directly, with no reverse proxy in front of it.
        iifname "sfp0" oifname "unifi" ip saddr { ${trusted} } tcp dport 443 accept
        # This guest-to-guest probe needs a rule separate from off-segment egress.
        iifname "uptime-kuma" oifname "unifi" tcp dport 443 accept

        # DNS serves every client inside the perimeter.
        iifname { ${guests} } oifname "dns" udp dport 53 accept
        iifname { ${guests} } oifname "dns" tcp dport 53 accept
        iifname "sfp0" oifname "dns" udp dport 53 accept
        iifname "sfp0" oifname "dns" tcp dport 53 accept

        # Clients reach the proxy; each vhost's own source-IP allowlist gates the rest.
        iifname "sfp0" oifname "proxy" ip saddr { ${trusted}, ${dmz.subnet} } tcp dport { 80, 443 } accept
        # Health checks, OIDC backchannels and CI requests.
        iifname { "uptime-kuma", "forgejo", "pgadmin", "ci-runner" } oifname "proxy" tcp dport 443 accept
        # The proxy reaches each backend on the port guest-web.nix gives it.
        ${lib.concatStrings (lib.mapAttrsToList (name: e: "iifname \"proxy\" oifname \"${name}\" tcp dport ${toString e.port} accept\n") web.endpoints)}

        # Allow only the egress declared by each guest.
        ${egressRules}

        # Drop multicast copies flooded to other taps without logging them.
        iifname "vault" ip daddr { 224.0.0.251, 239.255.255.250 } drop

        iifname { ${guests} } limit rate 10/second log prefix "guest-egress-drop "
      }
    '';
  };
}
