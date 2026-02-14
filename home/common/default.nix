# Common home configuration for all hosts
{ config, pkgs, ... }:

{
  imports = [
    ./zsh.nix
    ./git.nix
    ./nvim.nix
    ./packages.nix
  ];

}
