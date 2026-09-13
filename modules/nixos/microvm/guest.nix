{
  gateway,
  resolver,
  proxyAddress,
  monitoringAddress,
  nodeExporterPort,
  consoleKey,
  proxiedPorts,
}: {
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../host.nix
    ../../nix-settings.nix
    ../security.nix
  ];

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
          description = "Destination ports; empty allows any port of this protocol.";
        };

        sourcePorts = lib.mkOption {
          type = lib.types.listOf lib.types.port;
          default = [];
          description = "Source ports; empty allows any source port.";
        };
        destinations = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Destination addresses or prefixes. Empty excludes private networks; explicit destinations may include them.";
        };
      };
    });
    default = [];
    description = "Outbound flows allowed across the host bridge. Empty denies off-segment egress.";
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
      # microvm.nix manages the overlay on the read-only host store.
      shares = [
        {
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "virtiofs";
        }
      ];
      writableStoreOverlay = "/nix/.rw-store";
      balloon = lib.mkDefault true;
      deflateOnOOM = true;
    };

    # The CI runner adds disk swap below zram's priority.
    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = "zstd";
      memoryPercent = 30;
      priority = 100;
    };

    boot.kernel.sysctl."vm.swappiness" = lib.mkDefault 100;

    # The guest overlay cannot hardlink into the read-only host store.
    nix.settings.auto-optimise-store = lib.mkForce false;

    sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    # Use the host's NTS-synchronised clock through kvm-clock.
    services.timesyncd.enable = false;

    services.prometheus.exporters.node = {
      enable = true;
      port = nodeExporterPort;
    };

    # Allow the VSOCK root console and Forgejo's Git user.
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

    networking.firewall.extraInputRules = lib.mkMerge [
      (lib.mkBefore ''
        ip saddr ${monitoringAddress} tcp dport ${toString nodeExporterPort} accept
      '')
      (lib.concatMapStrings (port: "ip saddr ${proxyAddress} tcp dport ${toString port} accept\n") proxiedPorts)
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
