# Zsh shell configuration
{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "docker" "sudo" ];
      theme = "robbyrussell";
    };

    shellAliases = {
      # Modern replacements
      ls = "eza";
      ll = "eza -la";
      la = "eza -a";
      lt = "eza --tree";
      cat = "bat";
      cd = "z";

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

    initExtra = ''
      # Zoxide init
      eval "$(zoxide init zsh)"

      # FZF
      eval "$(fzf --zsh)"

      # Fastfetch on startup
      fastfetch
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
}
