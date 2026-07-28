# Home configuration for user 'dinesh.reddy' on Mac
{
  config,
  pkgs,
  osConfig,
  lib,
  ...
}:

{
  imports = [
    ./packages.nix
  ];

  home.username = "dinesh.reddy";
  home.homeDirectory = "/Users/dinesh.reddy";

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  home.stateVersion = "26.11";

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
        "docker"
        "kubectl"
        "direnv"
      ];
      theme = "robbyrussell";
    };

    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      share = true;
      extended = true;
    };

    shellAliases = {
      # zoxide-backed cd so every jump trains the database
      cd = "z";
    };
    initContent = ''
      export PATH="/etc/profiles/per-user/dinesh.reddy/bin:$PATH"

      # oh-my-claudecode state (keep .omc out of repos)
      export OMC_STATE_DIR="$HOME/.claude/omc"

      # Claude Code OpenTelemetry → Grafana Cloud
      export CLAUDE_CODE_ENABLE_TELEMETRY=1
      export CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1
      export OTEL_METRICS_EXPORTER=otlp
      export OTEL_LOGS_EXPORTER=otlp
      export OTEL_TRACES_EXPORTER=otlp
      export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-prod-ap-south-0.grafana.net/otlp
      export OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative

      # Load secrets from sops-nix
      ${lib.optionalString (osConfig.sops.secrets ? juspay_api_key) ''
        if [[ -r "${osConfig.sops.secrets.juspay_api_key.path}" ]]; then
          export JUSPAY_API_KEY=$(cat "${osConfig.sops.secrets.juspay_api_key.path}")
        fi
      ''}
      ${lib.optionalString (osConfig.sops.secrets ? notion_api_key) ''
        if [[ -r "${osConfig.sops.secrets.notion_api_key.path}" ]]; then
          export NOTION_API_KEY=$(cat "${osConfig.sops.secrets.notion_api_key.path}")
        fi
      ''}
      ${lib.optionalString (osConfig.sops.secrets ? bitbucket_token) ''
        if [[ -r "${osConfig.sops.secrets.bitbucket_token.path}" ]]; then
          export BITBUCKET_TOKEN=$(cat "${osConfig.sops.secrets.bitbucket_token.path}")
        fi
      ''}
      ${lib.optionalString (osConfig.sops.secrets ? grafana_otlp_token) ''
        if [[ -r "${osConfig.sops.secrets.grafana_otlp_token.path}" ]]; then
          local _grafana_token
          _grafana_token=$(cat "${osConfig.sops.secrets.grafana_otlp_token.path}")
          export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic $(printf '542971:%s' "$_grafana_token" | base64 | tr -d '\n')"
        fi
      ''}

      # starship, zoxide and direnv init come from their home-manager modules

      # Add homebrew to PATH
      if [ -d /opt/homebrew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      # Aliases
      alias ll='eza -la'
      alias ls='eza'
      alias cat='bat --paging=never -p'
      alias grep='rg'
      alias find='fd'
      alias top='htop'

      jclaude() {
        local MODEL

        MODEL=$(curl -s \
          'https://grid.ai.juspay.net/models?return_wildcard_routes=false&include_model_access_groups=false&only_model_access_groups=false&include_metadata=false' \
          -H 'accept: application/json' \
          -H "Authorization: Bearer $JUSPAY_API_KEY" |
          jq -r '.data[].id' | fzf)

        [[ -z "$MODEL" ]] && return 1

        env \
          GEMINI_API_KEY="" \
          GOOGLE_CLOUD_PROJECT="" \
          GOOGLE_APPLICATION_CREDENTIALS="" \
          CLAUDE_CODE_USE_VERTEX="" \
          CLOUD_ML_REGION="" \
          GOOGLE_VERTEX_PROJECT="" \
          ANTHROPIC_VERTEX_PROJECT_ID="" \
          ANTHROPIC_BASE_URL="https://grid.ai.juspay.net/" \
          ANTHROPIC_AUTH_TOKEN="$JUSPAY_API_KEY" \
          ANTHROPIC_MODEL="$MODEL" \
          ANTHROPIC_SMALL_FAST_MODEL="$MODEL" \
          CLAUDE_CODE_SUBAGENT_MODEL="$MODEL" \
          DISABLE_INTERLEAVED_THINKING=true \
          API_TIMEOUT_MS=600000 \
          BASH_MAX_TIMEOUT_MS=300000 \
          CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 \
          claude "$@"
      }
    '';
  };

  # Starship configuration
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      format = "$directory$git_branch$git_state$git_status$nix_shell$character";
      right_format = "$cmd_duration$time";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = false;
      };
      # Shown whenever a nix dev shell is active (direnv/nix-direnv sets IN_NIX_SHELL)
      nix_shell = {
        disabled = false;
        format = "[$symbol$state( \\($name\\))]($style) ";
        symbol = "❄️ ";
        style = "bold blue";
        impure_msg = "impure";
        pure_msg = "pure";
        unknown_msg = "nix";
        heuristic = true;
      };
    };
  };

  # zoxide - `z <dir>` jump, `zi` interactive pick
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # direnv + nix-direnv - auto-load flake dev shells per directory
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config.global = {
      # nix-direnv exports a lot; the per-cd env diff is pure noise
      hide_env_diff = true;
      # first flake eval in a repo legitimately takes a while
      warn_timeout = "30s";
    };
  };

  # Weekly direnv cache/gcroot pruning lives in hosts/macbook/admin.nix
  # (launchd daemon "direnv-prune", runs as this user)

  # Git configuration
  programs.git = {
    enable = true;
    settings = {
      user.name = "Dinesh Jagadam";
      user.email = "dinesh.reddy@juspay.in";
      init.defaultBranch = "main";
      core.editor = "nvim";
      pull.rebase = true;
    };
  };

  # Neovim config owned by chezmoi; install binary only + shell aliases
  home.shellAliases = {
    vi = "nvim";
    vim = "nvim";
  };

  # Emacs binary for Doom. macport build = native macOS window system + titlebar,
  # aarch64-darwin only (this file is macbook-specific anyway).
  programs.emacs = {
    enable = true;
    package = pkgs.emacs30-macport;
  };

  # Doom Emacs: ~/.config/emacs is the doom checkout (imperative, like nvim's
  # chezmoi-owned config); ~/.config/doom holds init.el/config.el/packages.el.
  home.sessionPath = [ "${config.home.homeDirectory}/.config/emacs/bin" ];

  home.activation.doomEmacsBootstrap = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    doomRepo="${config.home.homeDirectory}/.config/emacs"
    if [ ! -e "$doomRepo" ]; then
      # Network failure must not abort the whole rebuild
      if run ${pkgs.git}/bin/git clone --depth 1 \
           https://github.com/doomemacs/doomemacs "$doomRepo"; then
        echo "doom cloned to $doomRepo - finish with: ~/.config/emacs/bin/doom install"
      else
        echo "warning: doom clone failed; rerun activation or clone by hand" >&2
      fi
    fi
  '';

  # Fzf configuration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
    ];
  };

  # Bat configuration
  programs.bat = {
    enable = true;
    config = {
      theme = "Dracula";
    };
  };

  # Eza configuration
  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
  };

  # Tmux configuration
  programs.tmux = {
    enable = true;
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    keyMode = "vi";
    prefix = "C-a";
    terminal = "tmux-256color";
    historyLimit = 50000;

    plugins = with pkgs.tmuxPlugins; [
      sensible
      vim-tmux-navigator
      yank
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-nvim "session"
          set -g @resurrect-capture-pane-contents "on"
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore "on"
          set -g @continuum-save-interval "10"
        '';
      }
      {
        plugin = minimal-tmux-status;
        extraConfig = ''
          set -g @minimal-tmux-justify "left"
          set -g @minimal-tmux-indicator-str "  TMUX  "
          set -g @minimal-tmux-bg "#698DDA" # Zellij blue
        '';
      }
    ];

    extraConfig = ''
      # Truecolor
      set -ga terminal-overrides ",*256col*:Tc"

      # Renumber windows when one closes
      set -g renumber-windows on

      # Add thin pane borders similar to Zellij frames
      set -g pane-border-style fg='#444444'
      set -g pane-active-border-style fg='#258AAA'

      # Splits open in current path, intuitive keys
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      # Vi-style copy mode selection
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel

      # Quick config reload
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"

      # Resize panes with prefix + HJKL
      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5
    '';
  };
  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "less";
    LESS = "-R";

    # Doom looks these up; set explicitly so `doom` works from any shell
    EMACSDIR = "${config.home.homeDirectory}/.config/emacs";
    DOOMDIR = "${config.home.homeDirectory}/.config/doom";
  };
}
