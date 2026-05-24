# Pin jellyfin-desktop to nixpkgs commit where it builds on darwin
{ inputs, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      jellyfin-desktop = inputs.nixpkgs-jellyfin.legacyPackages.${prev.system}.jellyfin-desktop;
    })
  ];
}
