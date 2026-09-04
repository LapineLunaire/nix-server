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
  } @ inputs: let
    inherit (self) outputs;

    forHostSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];

    # The nixpkgs instance carries pkgs/ as an overlay, so a package of ours is reachable as pkgs.<name> from any module.
    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [(final: _prev: import ./pkgs final)];
        config.allowUnfree = true;
      };

    specialArgs = {inherit inputs outputs;};

    # A full host: impermanence, sops, and home-manager under the host's own modules.
    mkHost = {
      system,
      modules,
    }:
      nixpkgs.lib.nixosSystem {
        inherit specialArgs;
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
                extraSpecialArgs = specialArgs;
                sharedModules = [nixvim.homeModules.nixvim];
              };
            }
            ./users/carmilla
          ]
          ++ modules;
      };
    # Each hypervisor supplies its own guest data and its own guest directory, so adding a second one is an entry here plus its own files.
    hypervisors = {
      sparkle = {
        system = "x86_64-linux";
        guestDir = ./hosts/sparkle/guests;
        registry = import ./hosts/sparkle/guest-registry.nix;
        # Handed to every guest as module arguments.
        dmz = import ./hosts/sparkle/dmz-net.nix;
        net = import ./hosts/sparkle/guest-net.nix;
        web = import ./hosts/sparkle/guest-web.nix;
        trustedSubnets = import ./hosts/sparkle/trusted-subnets.nix;
        tunnelWeb = import ./hosts/sparkle/tunnel-web.nix;
        # sparkle's SSH host public key, authorized for root on every guest so `microvm -s` reaches the VSOCK console.
        consoleKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJ+Zb08V2BIx3TnFgha04A55Vo9d0ftNpNvnRgfO3Gk";
        # Five octets. The first is 02, whose low two bits mark the address locally administered and unicast, so it stays clear of vendor-assigned ranges. The other four are random. identity.nix appends the guest's index as the sixth octet.
        macPrefix = "02:76:96:0e:fe";
        # Guests needing extra flake-input modules name them here.
        extraModules = {
          qbittorrent = [vpn-confinement.nixosModules.default];
          unifi = [unifi-os-server.nixosModules.unifi-os-server];
        };
      };
    };

    # A guest: impermanence, microvm, and sops under the shared guest base, the guest's identity, and its own config. Guests carry no interactive user, so no home-manager.
    # The guest data is passed through specialArgs, so a guest reads net.vmAddress.<name> and holds no path to its own location.
    mkGuest = hv: name:
      nixpkgs.lib.nixosSystem {
        specialArgs = specialArgs // {inherit (hv) dmz net web trustedSubnets tunnelWeb;};
        modules =
          [
            {nixpkgs.pkgs = pkgsFor hv.system;}
            impermanence.nixosModules.impermanence
            microvm.nixosModules.microvm
            sops-nix.nixosModules.sops
            (outputs.lib.mkMicrovmGuest {
              inherit (hv) consoleKey;
              inherit (hv.net) nodeExporterPort;
              # The guests route through the DMZ router, as peers on the segment.
              gateway = hv.dmz.gateway;
              resolver = hv.net.vmAddress.dns;
              proxyAddress = hv.net.vmAddress.proxy;
              monitoringAddress = hv.net.vmAddress.monitoring;
              proxiedPorts = nixpkgs.lib.optional (hv.web.endpoints ? ${name}) hv.web.endpoints.${name}.port;
            })
            (outputs.lib.mkMicrovmIdentity {
              inherit name;
              inherit (hv) macPrefix;
              inherit (hv.registry.${name}) index;
              inherit (hv.dmz) prefixLength;
              address = hv.net.vmAddress.${name};
            })
            (hv.guestDir + "/${name}")
          ]
          ++ (hv.extraModules.${name} or []);
      };

    # One nixosConfiguration per registry entry across every hypervisor. Guest names share a namespace with the hosts, so a name declared by two hypervisors is raised here as an evaluation error.
    guestConfigurations = let
      perHypervisor = nixpkgs.lib.mapAttrsToList (_: hv: nixpkgs.lib.mapAttrs (name: _: mkGuest hv name) hv.registry) hypervisors;
      names = nixpkgs.lib.concatMap nixpkgs.lib.attrNames perHypervisor;
      duplicates = nixpkgs.lib.subtractLists (nixpkgs.lib.unique names) names;
    in
      if duplicates != []
      then throw "guest name declared by more than one hypervisor: ${nixpkgs.lib.concatStringsSep ", " duplicates}"
      else nixpkgs.lib.foldl' (a: b: a // b) {} perHypervisor;
  in {
    # Platform-neutral modules, read by the NixOS base and by the microVM guest base.
    modules = {
      host = ./modules/host.nix;
      nix-settings = ./modules/nix-settings.nix;
    };

    # Shared modules addressable as outputs.nixosModules.<name> from any nesting depth.
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

    # Functions from a parameter set to a module. Call them with their arguments in imports.
    lib = {
      # Takes { pool, startAt }.
      mkBorgBackup = import ./modules/nixos/borg-backup.nix;
      # The microVM framework, each taking the guest data it needs.
      mkMicrovmGuest = import ./modules/nixos/microvm/guest.nix;
      mkMicrovmIdentity = import ./modules/nixos/microvm/identity.nix;
      mkMicrovmHost = import ./modules/nixos/microvm/host.nix;
    };

    formatter = forHostSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    devShells = forHostSystems (system: let
      pkgs = pkgsFor system;
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
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

    packages = forHostSystems (system: import ./pkgs (pkgsFor system));

    nixosConfigurations =
      {
        sparkle = mkHost {
          system = "x86_64-linux";
          modules = [microvm.nixosModules.host lanzaboote.nixosModules.lanzaboote ./hosts/sparkle];
        };

        sparxie = mkHost {
          system = "aarch64-linux";
          modules = [./hosts/sparxie];
        };
      }
      // guestConfigurations;
  };
}
