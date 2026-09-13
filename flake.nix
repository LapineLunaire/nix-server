{
  description = "Carmilla's server config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-compat.url = "github:NixOS/flake-compat/master";

    rust-overlay = {
      url = "github:oxalica/rust-overlay/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    impermanence = {
      url = "github:nix-community/impermanence/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.pre-commit.inputs.flake-compat.follows = "flake-compat";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement/master";

    unifi-os-server = {
      url = "github:rcambrj/unifi-os-server";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nixvim,
    impermanence,
    lanzaboote,
    microvm,
    sops-nix,
    unifi-os-server,
    vpn-confinement,
    ...
  }: let
    forEachSystem = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];

    overlays = import ./overlays.nix;

    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [overlays.additions];
        config.allowUnfree = true;
      };

    mkHost = {
      system,
      modules,
    }:
      nixpkgs.lib.nixosSystem {
        modules =
          [
            {nixpkgs.pkgs = pkgsFor system;}
            impermanence.nixosModules.impermanence
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "bak";
                sharedModules = [nixvim.homeModules.nixvim];
              };
            }
            ./users/carmilla
          ]
          ++ modules;
      };
    guestConfigurations = let
      registry = import ./hosts/sparkle/guest-registry.nix;
      dmz = import ./hosts/sparkle/dmz-net.nix;
      net = import ./hosts/sparkle/guest-net.nix;
      web = import ./hosts/sparkle/guest-web.nix;
      trustedSubnets = import ./hosts/sparkle/trusted-subnets.nix;
      tunnelWeb = import ./hosts/sparkle/tunnel-web.nix;
      extraModules = {
        qbittorrent = [vpn-confinement.nixosModules.default];
        unifi = [unifi-os-server.nixosModules.unifi-os-server];
      };
    in
      nixpkgs.lib.mapAttrs (name: guest:
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit dmz net web trustedSubnets tunnelWeb;
            zoneSerial = self.lastModified;
          };
          modules =
            [
              {nixpkgs.pkgs = pkgsFor "x86_64-linux";}
              impermanence.nixosModules.impermanence
              microvm.nixosModules.microvm
              sops-nix.nixosModules.sops
              (import ./modules/nixos/microvm/guest.nix {
                # Sparkle's SSH host key authenticates the VSOCK console.
                consoleKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJ+Zb08V2BIx3TnFgha04A55Vo9d0ftNpNvnRgfO3Gk";
                inherit (net) nodeExporterPort;
                inherit (dmz) gateway;
                resolver = net.vmAddress.dns;
                proxyAddress = net.vmAddress.proxy;
                monitoringAddress = net.vmAddress.monitoring;
                proxiedPorts = nixpkgs.lib.optional (web.endpoints ? ${name}) web.endpoints.${name}.port;
              })
              (import ./modules/nixos/microvm/identity.nix {
                inherit name;
                inherit (guest) index;
                inherit (dmz) prefixLength;
                macPrefix = "02:76:96:0e:fe";
                address = net.vmAddress.${name};
              })
              (./hosts/sparkle/guests + "/${name}")
            ]
            ++ (extraModules.${name} or []);
        })
      registry;
  in {
    nixosModules = {
      host-base = ./modules/nixos/host-base;
      secure-boot = ./modules/nixos/secure-boot.nix;
      security = ./modules/nixos/security.nix;
      trusted-ssh-ingress = ./modules/nixos/trusted-ssh-ingress.nix;
      zfs = ./modules/nixos/zfs.nix;
      acme = ./modules/nixos/acme.nix;
      auto-update = ./modules/nixos/auto-update.nix;
      caddy = ./modules/nixos/caddy.nix;
      microvm-docker-common = ./modules/nixos/microvm/docker-common.nix;
      postgresql-passwords = ./modules/nixos/postgresql-passwords.nix;
      ssh-ip-whitelist = ./modules/nixos/ssh-ip-whitelist.nix;
      wireguard-tunnel = ./modules/nixos/wireguard-tunnel.nix;
    };

    lib = {
      mkBorgBackup = import ./modules/nixos/borg-backup.nix;
      mkMicrovmGuest = import ./modules/nixos/microvm/guest.nix;
      mkMicrovmIdentity = import ./modules/nixos/microvm/identity.nix;
      mkMicrovmHost = import ./modules/nixos/microvm/host.nix;
    };

    formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    devShells = forEachSystem (system: let
      pkgs = pkgsFor system;
    in {
      default = pkgs.mkShell {
        # Prefer uutils interactively; build dependencies retain GNU tools.
        packages = with pkgs; [
          uutils-coreutils-noprefix
          uutils-findutils
          uutils-diffutils
          alejandra
          nixd
          sops
          ssh-to-age
        ];

        shellHook = ''
          git config core.hooksPath .githooks
        '';
      };
    });

    packages = forEachSystem (system: import ./pkgs (pkgsFor system));

    nixosConfigurations =
      {
        sparkle = mkHost {
          system = "x86_64-linux";
          modules = [
            {_module.args = {inherit guestConfigurations;};}
            microvm.nixosModules.host
            lanzaboote.nixosModules.lanzaboote
            ./hosts/sparkle
          ];
        };

        sparxie = mkHost {
          system = "aarch64-linux";
          modules = [./hosts/sparxie];
        };
      }
      // guestConfigurations;
  };
}
