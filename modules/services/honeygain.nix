# Honeygain bandwidth sharing container
{ config, pkgs, ... }:

{
  virtualisation.oci-containers = {
    backend = "docker";

    containers.honeygain = {
      image = "honeygain/honeygain";
      autoStart = true;

      # CLI flags are REQUIRED
      cmd = [
        "-tou-accept"
        "-email" "dineshjagadam@gmail.com"
        "-pass" "Basha@606"
        "-device" "nauvoo"
      ];
    };
  };
}
