# Zsh shell configuration
{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "eza"
        "fzf"
        "direnv"
        "colorize"
        "docker"
        "cabal"
        "golang"
        "gradle"
        "man"
        "node"
        "npm"
        "nvm"
        "vscode"
        "zsh-interactive-cd"
        "zsh-navigation-tools"
      ];
      theme = "xiong-chiamiov-plus";
    };

    shellAliases = {
      # Modern replacements
      ls = "eza";
      ll = "eza -la";
      la = "eza -a";
      lt = "eza --tree";
      cd = "z";
      reload = "source ~/.zshrc";

      # Nix shortcuts
      nrs = "sudo nixos-rebuild switch --flake ~/repos/nixos-config#nauvoo";
      nrb = "sudo nixos-rebuild build --flake ~/repos/nixos-config#nauvoo";
      nfu = "nix flake update ~/repos/nixos-config";
      hms = "home-manager switch --flake ~/repos/nixos-config";

      # Git
      g = "git";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gs = "git status";
      gd = "git diff";
      gl = "git log --oneline --graph";

      # Utils
      ".." = "cd ..";
      "..." = "cd ../..";
      mkdir = "mkdir -p";
    };

    initContent = ''
      # Direnv hook
      eval "$(direnv hook zsh)"

      # Zoxide init
      eval "$(zoxide init zsh)"

      # FZF
      eval "$(fzf --zsh)"

      # pay-respects
      command -v pay-respects >/dev/null && eval "$(pay-respects init zsh)"

      # Fastfetch on startup (only for interactive terminals)
      if [[ -t 1 ]]; then
        command -v fastfetch >/dev/null && fastfetch
      fi

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

      # jclaude function - Juspay AI grid wrapper
      jclaude() {
        local MODEL

        if [[ -z "$JUSPAY_API_KEY" ]]; then
          echo "Error: JUSPAY_API_KEY not set" >&2
          return 1
        fi

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

      # gswt - git worktree switcher with fzf
      gswt() {
        cd "$(_fzf_git_worktrees --no-multi)"
      }
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
  };

  programs.bat = {
    enable = true;
    config.theme = "TwoDark";
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    pay-respects
    jq
    curl
  ];
}
