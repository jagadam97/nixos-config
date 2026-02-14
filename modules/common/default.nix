# Common configuration applied to all hosts
{ config, pkgs, lib, ... }:

{
  imports = [
    ./base.nix
    ./users.nix
    ./ssh.nix
    ./nix-settings.nix
  ];
}
