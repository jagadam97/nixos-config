# Packages migrated from Homebrew
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Secret management
    sops
    age

    # Development Tools
    neovim
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
    pay-respects
    # direnv, starship and zoxide come from their home-manager modules

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

    # Database Clients
    mariadb.client
    postgresql
    redis

    # AWS / Cloud
    awscli2
    ssm-session-manager-plugin
    kubectl

    # Network Tools
    wget
    curl
    rsync
    mosh
    uv
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
    herdr

    # Documentation
    pandoc

    # Encryption
    gnupg

    # Media Tools
    ffmpeg
    tesseract
    sqlite
    jellyfin-desktop

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
