# Common packages for all users
{ config, pkgs, osConfig, ... }:

let isKayda = osConfig.networking.hostName == "kayda";

in

{
  home.packages = with pkgs; [
    # System utilities (all hosts)
    mosh
    ffmpeg
  ] ++ (if !isKayda then [
    # Dev tools (workstations only)
    go
    cmake
    gcc
    aria2
    chafa
    zellij
  ] else []);
}
