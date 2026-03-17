# TTY1 Dashboard - Auto-login with tmux layout:
#   left-top: htop | left-bottom: nvtop | right: journalctl
# Switch to other TTYs with Alt+F2 through Alt+F6 for normal login
{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Never blank the screen
  boot.kernelParams = [ "consoleblank=0" ];

  # Auto-login jagadam97 on TTY1
  services.getty.autologinUser = "jagadam97";

  # Launch dashboard from jagadam97's shell on auto-login
  environment.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ] && [ "$(id -un)" = "jagadam97" ]; then
      # Kill any stale session
      ${pkgs.tmux}/bin/tmux kill-session -t dashboard 2>/dev/null || true

      # Layout: left-top = htop, left-bottom = nvtop, right = journalctl
      ${pkgs.tmux}/bin/tmux new-session -d -s dashboard \; \
        send-keys "${pkgs.htop}/bin/htop" Enter \; \
        split-window -v \; \
        send-keys "${pkgs.nvtop}/bin/nvtop" Enter \; \
        split-window -h -t 0 \; \
        send-keys "journalctl -f" Enter \; \
        select-pane -t 0

      exec ${pkgs.tmux}/bin/tmux attach-session -t dashboard
    fi
  '';
}
