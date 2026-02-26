# Home configuration for user 'dinesh.reddy' on Mac
{ config, pkgs, ... }:

{
  imports = [
    ./packages.nix
  ];

  home.username = "dinesh.reddy";
  home.homeDirectory = "/Users/dinesh.reddy";

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  home.stateVersion = "26.05";

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" "docker" "kubectl" ];
      theme = "robbyrussell";
    };
    initContent = ''
      export PATH="/etc/profiles/per-user/dinesh.reddy/bin:$PATH"
      # Starship prompt
      eval "$(starship init zsh)"

      # zoxide
      eval "$(zoxide init zsh)"

      # Add homebrew to PATH
      if [ -d /opt/homebrew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi

      # Aliases
      alias ll='eza -la'
      alias ls='eza'
      alias cat='bat'
      alias grep='rg'
      alias find='fd'
      alias top='htop'

      # Load secrets helper
      load_juspay_api_key() {
        local secret_file="$HOME/repos/nixos-config/hosts/macbook/secrets.yaml"
        if [[ -f "$secret_file" ]]; then
          export JUSPAY_API_KEY=$(sops --decrypt "$secret_file" | jq -r '.juspay_api_key')
        else
          echo "Secret file not found: $secret_file" >&2
          return 1
        fi
      }

      # Auto-load if secrets file exists
      if [[ -f "$HOME/repos/nixos-config/hosts/macbook/secrets.yaml" ]]; then
        load_juspay_api_key 2>/dev/null || true
      fi

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
    settings = {
      format = "$directory$git_branch$git_state$git_status$character";
      right_format = "$cmd_duration$time";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = false;
      };
    };
  };

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

  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # Fzf configuration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [ "--height 40%" "--layout=reverse" "--border" ];
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
    clock24 = true;
    baseIndex = 1;
    escapeTime = 0;
    keyMode = "vi";
  };

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "less";
    LESS = "-R";
  };
}