# Packages for jagadam97 - split into server essentials and dev tools
{ config, pkgs, osConfig, ... }:

let isKayda = osConfig.networking.hostName == "kayda";

in

{
  home.packages = with pkgs; [
    # Secret management
    sops
    age

    # Server / admin essentials
    git
    fzf
    ripgrep
    fd
    bat
    eza
    jq
    yq
    tree
    htop
    btop
    glances
    tmux
    ncdu
    nano
    direnv
    pay-respects
    nix-index
    starship
    zoxide

    # Network
    wget
    curl
    rsync
    mosh

    # Compression
    gzip
    bzip2
    xz
    unzip
    zip
    zstd

    # Text processing
    gawk
    gnused
    gnugrep
    coreutils
    findutils

    # Encryption
    gnupg

    # Media (Jellyfin transcoding)
    ffmpeg

    # Fonts
    nerd-fonts.jetbrains-mono
  ] ++ (if !isKayda then [
    # --- Workstation-only packages below ---

    # Terminal / GUI
    alacritty
    zed-editor

    # Dev workflow
    lazygit
    chezmoi
    gh
    aria2
    chafa

    # Nix language servers
    nil
    nixd

    # Build tools
    gcc
    cmake
    ninja
    gnumake
    autoconf
    automake
    libtool
    pkg-config
    ccache

    # Languages
    go
    nodejs
    python3
    ruby
    openjdk
    llvm
    clang-tools

    # Python
    pyenv
    black

    # Haskell
    hlint
    stylish-haskell

    # OCaml
    ocaml
    opam
    dune

    # Containers
    docker
    docker-compose
    podman
    podman-compose

    # Database clients
    mariadb.client
    postgresql
    redis

    # Cloud
    awscli2
    kubectl

    # GUI / desktop tools
    putty
    scrcpy

    # Documentation / misc
    pandoc
    tesseract
    sqlite
    protobuf

    # AI tools
    claude-code
    github-copilot
  ] else []);
}
