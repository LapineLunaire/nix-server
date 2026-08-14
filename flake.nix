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
    nixpkgs-unstable,
    home-manager,
    nixvim,
    impermanence,
    sops-nix,
    ...
  } @ inputs: let
    inherit (self) outputs;

    forHostSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];

    # Every nixpkgs instance carries pkgs/ as an overlay, so a package of ours is reachable as pkgs.<name> from any module.
    mkPkgs = np: system:
      import np {
        inherit system;
        overlays = [(final: _prev: import ./pkgs final)];
        config.allowUnfree = true;
      };
    pkgsFor = mkPkgs nixpkgs;
    pkgsUnstableFor = mkPkgs nixpkgs-unstable;

    # Every NixOS and home-manager module also receives a nixpkgs-unstable instance carrying the same overlay, for pulling individual packages ahead of their nixpkgs.
    specialArgsFor = system: {
      inherit inputs outputs;
      pkgsUnstable = pkgsUnstableFor system;
    };

    # A full host: impermanence, sops, and home-manager under the host's own modules.
    mkHost = {
      system,
      modules,
    }: let
      specialArgs = specialArgsFor system;
    in
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
  in {
    # Shared modules addressable as outputs.nixosModules.<name> from any nesting depth.
    nixosModules = {
      host = ./modules/host.nix;
      nix-settings = ./modules/nix-settings.nix;
      host-base = ./modules/nixos/host-base;
      security = ./modules/nixos/security.nix;
      zfs = ./modules/nixos/zfs.nix;
      acme = ./modules/nixos/acme.nix;
      caddy = ./modules/nixos/caddy.nix;
      postgresql-passwords = ./modules/nixos/postgresql-passwords.nix;
    };

    # Functions from a parameter set to a module, rather than modules themselves. Call them with their arguments instead of listing them in imports.
    lib = {
      # Takes { pool, startAt }.
      mkBorgBackup = import ./modules/nixos/borg-backup.nix;
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

    nixosConfigurations = {
      sparxie = mkHost {
        system = "aarch64-linux";
        modules = [./hosts/sparxie];
      };
    };
  };
}
