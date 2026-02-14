# Honeygain bandwidth sharing container
{ config, pkgs, ... }:

{
  sops.secrets.honeygain_email = { };
  sops.secrets.honeygain_password = { };

  virtualisation.oci-containers.containers.honeygain = {
    image = "honeygain/honeygain";
    autoStart = true;
    environmentFiles = [
      config.sops.secrets.honeygain_email.path
      config.sops.secrets.honeygain_password.path
    ];
    cmd = [
      "-tou-accept"
      "-email-file" "/run/secrets/honeygain_email"
      "-pass-file" "/run/secrets/honeygain_password"
      "-device" "nauvoo"
    ];
  };
}
