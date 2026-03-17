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

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      darwin,
      home-manager,
      sops-nix,
      disko,
      ...
    }@inputs:
    let
      linuxSystem = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        # Nauvoo - your main desktop/workstation
        nauvoo = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
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
            ./modules/services/nginx.nix # Uncomment to enable TCP/UDP stream proxy

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

        # Razorback - workstation system
        razorback = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; };
          modules = [
            sops-nix.nixosModules.sops
            ./hosts/razorback
            ./modules/common
            ./modules/desktop
            ./modules/services/docker.nix
            ./modules/services/cachix.nix
            ./modules/services/disable-suspend.nix
            ./modules/services/nix-ld.nix

            # Home Manager integration
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.users.jagadam97 = import ./home/users/jagadam97;
            }
          ];
        };

        # Kayda - Laptop homelab server (GTX 1050 Ti Mobile)
        kayda = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          specialArgs = { inherit inputs; };
          modules = [
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            ./hosts/kayda
            ./modules/common
            ./modules/nvidia
            ./modules/dashboard
            ./modules/services/disable-suspend.nix
            ./modules/services/nix-ld.nix
            ./modules/services/nixos-autoupdate.nix

            # Home Manager integration
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.users.jagadam97 = import ./home/users/jagadam97;
            }
          ];
        };
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
