{
  description = "NixOS configuration for Nauvoo and other machines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager, sops-nix, ... }@inputs:
    let
      linuxSystem = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        # Nauvoo - your main desktop/workstation
        nauvoo = nixpkgs.lib.nixosSystem {
          inherit linuxSystem;
          specialArgs = { inherit inputs; };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/nauvoo
            ./modules/common
            ./modules/desktop
            ./modules/services/docker.nix
            ./modules/services/telegraf.nix
            ./modules/services/wireguard.nix
            ./modules/services/cachix.nix
            ./modules/services/nomad.nix
            ./modules/services/foldingathome.nix
            ./modules/services/honeygain.nix
            ./modules/services/flaresolver.nix
            ./modules/services/disable-suspend.nix
            ./modules/services/nix-ld.nix
            # ./modules/services/nginx.nix  # Uncomment to enable TCP/UDP stream proxy

            # Home Manager integration
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.users.dj = import ./home/users/dj;
            }
          ];
        };

        # Add more machines here:
        # laptop = nixpkgs.lib.nixosSystem { ... };
        # server = nixpkgs.lib.nixosSystem { ... };
      };

      darwinConfigurations = {
        # MacBook - Apple Silicon Mac
        macbook = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/macbook
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.users."dinesh.reddy" = import ./home/users/dinesh.reddy;
            }
          ];
        };
      };
    };
}
