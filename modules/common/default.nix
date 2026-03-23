# Common configuration applied to all hosts
{ config, pkgs, lib, ... }:

{
  imports = [
    ./base.nix
    ./users.nix
    ./nix-settings.nix
  ];
}
