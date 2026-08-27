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

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs-jellyfin.url = "github:NixOS/nixpkgs/4c1018dae018162ec878d42fec712642d214fdfa";

    # The scraper is packaged in its own repo; this pulls that build. Fetched
    # over https, not git+ssh: CI runners have no SSH key, and the ssh URL also
    # defaulted to a nonexistent 'master' ref when HEAD could not be read.
    homelab-scrapper = {
      url = "github:jagadam97/homelab-scrapper";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Push-based deploys for pella. Chosen over colmena for magic rollback: the
    # target reverts to the previous generation on its own if the deployer
    # cannot reconnect, which is the safety net a console-less box that is
    # about to become the household router actually needs.
    deploy-rs = {
      url = "github:serokell/deploy-rs";
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
      nixos-hardware,
      nix-index-database,
      nixpkgs-jellyfin,
      deploy-rs,
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
            disko.nixosModules.disko
            ./hosts/nauvoo
            ./overlays/nomad.nix
            ./modules/common
            ./modules/desktop
            ./modules/desktop/gnome.nix
            ./modules/services/docker.nix
            ./modules/services/telegraf.nix
            ./modules/services/wireguard.nix
            ./modules/services/cachix.nix
            ./modules/services/nomad.nix
            ./modules/services/honeygain.nix
            ./modules/services/flaresolver.nix
            ./modules/services/disable-suspend.nix
            ./modules/services/nix-ld.nix
            ./modules/services/nginx.nix # Uncomment to enable TCP/UDP stream proxy
            ./modules/services/nixos-autoupdate.nix
            nix-index-database.nixosModules.default
            { programs.nix-index-database.comma.enable = true; }

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
            disko.nixosModules.disko
            ./hosts/razorback
            ./overlays/jellyfin-desktop.nix
            ./modules/common
            ./modules/desktop
            ./modules/desktop/kde.nix
            ./modules/services/cachix.nix
            ./modules/services/nix-ld.nix
            ./modules/services/nfs-mounts.nix
            nix-index-database.nixosModules.default
            { programs.nix-index-database.comma.enable = true; }

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
            # ./modules/dashboard
            ./modules/services/disable-suspend.nix
            ./modules/services/nixos-autoupdate.nix
            ./modules/services/pella-autodeploy.nix
            ./modules/services/nfs-mounts.nix
            ./modules/services/jellyfin.nix
            ./modules/services/telegraf.nix
            ./modules/services/vector.nix
            ./modules/services/cachix.nix
            ./modules/services/flaresolver.nix
            ./modules/services/byparr.nix
            nix-index-database.nixosModules.default
            { programs.nix-index-database.comma.enable = true; }

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

        # Pella - Raspberry Pi 4 router (phase 1: NixOS only, routing is phase 2)
        pella = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            sops-nix.nixosModules.sops
            # nixos-hardware.nixosModules.raspberry-pi-4 is deliberately NOT
            # used: it pins linuxPackages_rpi4, which is not in
            # cache.nixos.org (404), so it would compile an ARM kernel plus a
            # ZFS module under qemu emulation. The generic aarch64 kernel is
            # cached (200) and is the standard sd-image-aarch64 path. The
            # RPi-specific initrd modules it would have added are set by hand
            # in hosts/pella/hardware.nix.
            ./hosts/pella
            ./modules/common
            ./modules/services/nfs-mounts.nix
            ./modules/services/homelab-scrapper.nix
            ./modules/services/filebrowser-quantum.nix
            ./modules/services/telegraf.nix
          ];
        };
      };

      darwinConfigurations = {
        # MacBook - Apple Silicon Mac
        macbook = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs; };
          modules = [
            nix-index-database.darwinModules.nix-index
            sops-nix.darwinModules.sops
            ./hosts/macbook
            ./overlays/jellyfin-desktop.nix
            home-manager.darwinModules.home-manager
            { programs.nix-index-database.comma.enable = true; }
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users."dinesh.reddy" = import ./home/users/dinesh.reddy;
            }
          ];
        };
      };

      # deploy-rs. Run from kayda, which builds aarch64 under binfmt and pushes
      # the finished closure, so pella never needs GitHub credentials for the
      # private homelab-scrapper input.
      #
      # hostname is the LAN address on purpose, not the Tailscale name: magic
      # rollback works by having the deployer reconnect after activation, and
      # activation can restart tailscaled. Over Tailscale that reconnect can
      # fail and roll back a perfectly good deploy. kayda is on the same
      # 192.168.4.0/24 subnet, so the LAN path stays up across activation.
      deploy.nodes.pella = {
        hostname = "192.168.4.230";
        profiles.system = {
          sshUser = "root";
          user = "root";
          path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.pella;
          magicRollback = true;
          autoRollback = true;
          confirmTimeout = 60;
        };
      };

      # Makes `nix flake check` validate the node definitions above.
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
