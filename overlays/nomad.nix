# Pin nomad to 2.0.3 (not yet in nixpkgs)
{ ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      nomad = prev.buildGo126Module rec {
        pname = "nomad";
        version = "2.0.3";

        src = prev.fetchFromGitHub {
          owner = "hashicorp";
          repo = "nomad";
          rev = "v${version}";
          hash = "sha256-gCpOxXwtBtq6qN5EKQmj9IKJe/5DwCB+W/GUhLvQQ4I=";
        };

        vendorHash = "sha256-UvgkQE5UJbbbEHFODnl1YeW2AGPvXul1hwswxPSbpNI=";

        subPackages = [ "." ];

        ldflags = [
          "-X github.com/hashicorp/nomad/version.Version=${version}"
          "-X github.com/hashicorp/nomad/version.VersionPrerelease="
          "-X github.com/hashicorp/nomad/version.BuildDate=1970-01-01T00:00:00Z"
        ];

        tags = [ "ui" ];

        nativeBuildInputs = [ prev.installShellFiles ];

        postInstall = ''
          echo "complete -C $out/bin/nomad nomad" > nomad.bash
          installShellCompletion nomad.bash
        '';

        meta = with prev.lib; {
          homepage = "https://developer.hashicorp.com/nomad";
          description = "Distributed, Highly Available, Datacenter-Aware Scheduler";
          license = licenses.bsl11;
          mainProgram = "nomad";
          platforms = platforms.linux ++ platforms.darwin;
        };
      };
    })
  ];
}
