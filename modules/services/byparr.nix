# Byparr - FlareSolverr-compatible Cloudflare bypass proxy.
#
# Upstream ships only a container image and isn't in nixpkgs; its deps
# (camoufox, playwright-captcha) aren't packaged either, and camoufox pulls a
# prebuilt Firefox at runtime. So we run it natively via `uv` from a git
# checkout, inside an FHS sandbox so the non-Nix Firefox/Python binaries find
# their shared libraries. Listens on 8192 to avoid the flaresolverr port (8191).
{ config, lib, pkgs, ... }:

let
  port = 8192;
  repo = "https://github.com/ThePhaseless/Byparr";

  # FHS env: provides uv/git plus the shared libs a playwright/camoufox Firefox
  # (and the uv-managed CPython 3.14 standalone build) expect at runtime.
  byparr-fhs = pkgs.buildFHSEnv {
    name = "byparr-env";
    targetPkgs = p: with p; [
      uv
      git
      cacert
      # toolchain / generic runtime
      stdenv.cc.cc
      zlib
      glibc
      # Firefox / camoufox runtime libraries
      glib
      nss
      nspr
      dbus
      atk
      at-spi2-atk
      at-spi2-core
      cups
      libdrm
      gtk3
      pango
      cairo
      gdk-pixbuf
      expat
      libxkbcommon
      mesa
      libgbm
      alsa-lib
      fontconfig
      freetype
      libGL
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
      libxrender
      libxtst
      libxi
      libxcursor
      libxscrnsaver
    ];
    runScript = pkgs.writeShellScript "byparr-run" ''
      set -euo pipefail

      # Keep all mutable state (venv, uv + camoufox caches, the checkout) under
      # the systemd StateDirectory (/var/lib/byparr).
      export HOME="$STATE_DIRECTORY"
      export UV_CACHE_DIR="$HOME/.cache/uv"
      export UV_PYTHON_INSTALL_DIR="$HOME/.local/uv-python"

      src="$HOME/Byparr"
      if [ ! -d "$src/.git" ]; then
        git clone --depth 1 ${repo} "$src"
      else
        git -C "$src" config pull.ff only
        git -C "$src" pull || true
      fi
      cd "$src"

      # Resolve deps from uv.lock and ensure the camoufox browser is present
      # (idempotent after the first boot; both need network the first time).
      uv sync --frozen
      uv run camoufox fetch

      exec uv run main.py
    '';
  };
in
{
  users.users.byparr = {
    isSystemUser = true;
    group = "byparr";
    home = "/var/lib/byparr";
  };
  users.groups.byparr = { };

  systemd.services.byparr = {
    description = "Byparr - Cloudflare bypass proxy (FlareSolverr-compatible)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOST = "0.0.0.0";
      PORT = toString port;
      LOG_LEVEL = "info";
      TZ = "Asia/Kolkata";
    };

    serviceConfig = {
      User = "byparr";
      Group = "byparr";
      StateDirectory = "byparr";
      WorkingDirectory = "/var/lib/byparr";

      ExecStart = "${byparr-fhs}/bin/byparr-env";

      # First boot fetches uv deps + a ~150MB browser, so allow a long start.
      TimeoutStartSec = "600s";
      Restart = "on-failure";
      RestartSec = 10;

      # Resource control (headless Firefox is heavy; this is a laptop).
      MemoryHigh = "2500M";
      MemoryMax = "3G";
      MemorySwapMax = "0";
      CPUQuota = "300%";

      # Light hardening — avoid namespace restrictions that would break the
      # FHS sandbox's bubblewrap.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
    };
  };
}
