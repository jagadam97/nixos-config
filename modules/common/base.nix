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
  ];
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;
  programs.zsh.ohMyZsh.enable = true;
  nixpkgs.config.allowUnfree = true;
  services.tailscale.enable = true;
}
