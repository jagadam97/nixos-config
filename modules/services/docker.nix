# Docker and virtualization
{ config, pkgs, ... }:

{
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  # Additional dev tools
  environment.systemPackages = with pkgs; [
    qemu
    qemu_kvm
    OVMF
    libvirt
  ];

  virtualisation.libvirtd.enable = true;
}
