{ config, pkgs, ... }:
{
  # Printing
  services.printing.enable = true;

  # Audio (PipeWire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # EasyEffects for EQ / bass control
  programs.dconf.enable = true;
  environment.systemPackages = with pkgs; [ easyeffects ];
}