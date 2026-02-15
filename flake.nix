{
  description = "NixOS configuration for Nauvoo and other machines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        # Nauvoo - your main desktop/workstation
        nauvoo = nixpkgs.lib.nixosSystem {
          inherit system;
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
              home-manager.users.dj = import ./home/users/dj;
            }
          ];
        };

        # Add more machines here:
        # laptop = nixpkgs.lib.nixosSystem { ... };
        # server = nixpkgs.lib.nixosSystem { ... };
      };
    };
}
