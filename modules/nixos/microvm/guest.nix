# The shared microVM guest baseline: security.nix hardening, virtiofs persistence, sops, node_exporter, and the sshd serving the root vsock console.
# Takes the addressing of the segment the guest joins and returns its module, so this file carries no host's addressing. gateway is the segment's router, resolver is the DNS the guest points at, proxyAddress is the reverse proxy allowed to reach its service ports, monitoringAddress is the guest allowed to scrape node_exporter on nodeExporterPort, proxiedPorts are the ports this guest is proxied on (generated from guest-web.nix, so a guest never names its own), and consoleKey is the host public key authorized for root over the vsock console.
{
  gateway,
  resolver,
  proxyAddress,
  monitoringAddress,
  nodeExporterPort,
  consoleKey,
  proxiedPorts,
}: {
  config,
  lib,
  outputs,
  pkgs,
  ...
}: {
  imports = [
    outputs.modules.host
    outputs.modules.nix-settings
    outputs.nixosModules.security
  ];

  options.microvmGuest.proxyReachableTCPPorts = lib.mkOption {
    type = lib.types.listOf lib.types.port;
    default = [];
    description = "TCP ports the reverse proxy may reach on this VM beyond the ports it is proxied on, which are generated. Each becomes an input-chain accept from the proxy's address.";
  };

  options.microvmGuest.egress = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        proto = lib.mkOption {
          type = lib.types.enum ["tcp" "udp" "icmp"];
          description = "Protocol this flow uses. icmp takes no ports.";
        };
        ports = lib.mkOption {
          type = lib.types.listOf lib.types.port;
          default = [];
          description = "Destination ports. Empty means every port of this protocol, which is what a guest whose outbound targets are runtime state needs.";
        };

        sourcePorts = lib.mkOption {
          type = lib.types.listOf lib.types.port;
          default = [];
          description = "Source ports, for a flow whose destination port is runtime state but whose own is fixed: a discovery daemon answering a probe on the prober's ephemeral port still answers from its own well-known port. Scoping such a flow here keeps it from having to be declared as every port of the protocol. Empty means any source port.";
        };
        destinations = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Destination addresses or prefixes. Empty means any address outside private space, which the host's rule excludes so an any-destination flow can never reach the management network or the LAN. Naming destinations here takes that exclusion off: the addresses are used as given, private or not.";
        };
      };
    });
    default = [];
    description = "Flows this guest may open outside the segment. Default-deny: a guest with no declaration reaches nothing off-segment. Narrow a guest where its destinations are fully determined by this configuration. Where they are runtime state, declare the protocols with no ports, so the flow keeps the reach the service needs.";
  };

  config = {
    environment.systemPackages = [pkgs.ghostty.terminfo];
    # /var/lib and /var/log bind-mounted from /persist (virtiofs share at /persist).
    fileSystems."/persist".neededForBoot = true;
    environment.persistence."/persist" = {
      directories = [
        "/var/lib"
        "/var/log"
      ];
      files = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
      ];
    };

    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = lib.mkDefault 4;
      mem = lib.mkDefault 2048;
      # Shared host nix store (read-only). Do NOT set fileSystems."/nix/store" manually; microvm.nix manages the overlay when writableStoreOverlay is set.
      shares = [
        {
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "virtiofs";
        }
      ];
      writableStoreOverlay = "/nix/.rw-store";
      # balloon is bool; initialBalloonMem (MB) sets starting size per VM.
      balloon = lib.mkDefault true;
      deflateOnOOM = true;
    };

    # Guest mem is fixed, with nothing to spill into.
    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = "zstd";
      memoryPercent = 30;
      priority = 100;
    };

    boot.kernel.sysctl."vm.swappiness" = lib.mkDefault 100;

    # nix-settings turns auto-optimise-store on for every system; a guest store is an overlay over the host's read-only store, which it cannot hardlink into, and microvm.nix asserts the two are never combined.
    nix.settings.auto-optimise-store = lib.mkForce false;

    sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    # Guests take time from kvm-clock, which tracks sparkle, and sparkle runs chrony with NTS. A per-guest NTP client would be a redundant outbound dependency for a clock it already has.
    services.timesyncd.enable = false;

    # node_exporter on every VM, scraped by the monitoring VM only.
    services.prometheus.exporters.node = {
      enable = true;
      port = nodeExporterPort;
    };

    # sshd serves the root VSOCK console (microvm -s) and, on git-ssh VMs, the service's git user.
    services.openssh = {
      enable = true;
      openFirewall = false;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AuthenticationMethods = "publickey";
      };
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };
    microvm.vsock.ssh.enable = true;
    users.users.root.openssh.authorizedKeys.keys = [consoleKey];

    assertions = [
      {
        assertion = !(lib.any (port: lib.elem port proxiedPorts) config.microvmGuest.proxyReachableTCPPorts);
        message = "microvmGuest.proxyReachableTCPPorts on ${config.networking.hostName} names a port guest-web.nix already declares; that accept is generated, remove the declaration.";
      }
    ];

    networking.firewall.extraInputRules = lib.mkMerge [
      (lib.mkBefore ''
        ip saddr ${monitoringAddress} tcp dport ${toString nodeExporterPort} accept
      '')
      (lib.concatMapStrings (port: "ip saddr ${proxyAddress} tcp dport ${toString port} accept\n") (proxiedPorts ++ config.microvmGuest.proxyReachableTCPPorts))
    ];
    networking.nftables.enable = true;
    networking.firewall.enable = true;
    networking.useDHCP = false;
    # Force eth0 naming; all VM configs reference eth0.
    networking.usePredictableInterfaceNames = false;
    networking.nameservers = [resolver];
    networking.defaultGateway = {
      address = gateway;
      interface = "eth0";
    };

    time.timeZone = "UTC";
    system.stateVersion = "26.05";
  };
}
