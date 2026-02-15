# Git configuration
{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    settings.user.name = "jagadam97";
    settings.user.email = "dineshjagadam@gmail.com";

    settings = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = false;
      core.editor = "nvim";
      merge.tool = "nvimdiff";
    };

    ignores = [
      ".DS_Store"
      "*.swp"
      "*.swo"
      "*~"
      ".direnv/"
      "result"
      "result-*"
    ];
  };

  # GitHub CLI
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };
}
