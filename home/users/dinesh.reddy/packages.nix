# Packages migrated from Homebrew
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Secret management
    sops
    age

    # Development Tools
    git lazygit chezmoi
    gh
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
    starship
    zoxide

    # From home/common/packages.nix
    go
    aria2
    chafa

    # Build Tools
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
    nodejs
    python3
    ruby
    openjdk
    llvm
    clang-tools

    # Python Tools
    pyenv
    black

    # Haskell Tools
    hlint
    stylish-haskell

    # OCaml Tools
    ocaml
    opam
    dune

    # Container Tools
    docker
    docker-compose
    podman
    podman-compose

    # Database Clients
    mariadb.client
    postgresql
    redis

    # AWS / Cloud
    awscli
    kubectl

    # Network Tools
    wget
    curl
    rsync
    mosh
    putty
    scrcpy

    # Compression
    gzip
    bzip2
    xz
    unzip
    zip
    zstd

    # Text Processing
    gawk
    gnused
    gnugrep
    coreutils
    findutils

    # Terminal Multiplexer
    tmux

    # Documentation
    pandoc

    # Encryption
    gnupg

    # Media Tools
    ffmpeg
    tesseract
    sqlite

    # Other
    protobuf

    # AI
    claude-code
    github-copilot-cli

    # Nix LSP
    nixd
    nil
  ];
}
