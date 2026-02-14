{ pkgs, ... }:

{
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Basic C libraries for Go/CGO and general binaries
    stdenv.cc.cc
    glibc
    zlib
    openssl
    curl
    expat

    # Common libraries for many tools
    libiconv
    gettext
    libxml2
    sqlite
  ];
}
