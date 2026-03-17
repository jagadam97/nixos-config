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

  # Note: Audio (PipeWire) and printing are in modules/desktop/pipewire.nix
  # They are intentionally excluded here to keep headless servers lean
}
