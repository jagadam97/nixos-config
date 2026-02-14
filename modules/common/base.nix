# Base system configuration
{ config, pkgs, ... }:

{
  # Basic system packages
  environment.systemPackages = with pkgs; [
    git
    wget
    neovim
    zsh
    htop
    btop
    tailscale
    ncdu
    eza
    fzf
    fastfetch
    chezmoi

    # Virtualization tools
    qemu
    OVMF
  ];

  # Shell
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;
  programs.zsh.ohMyZsh.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Tailscale
  services.tailscale.enable = true;

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
}
