# TTY1 Dashboard - Auto-login with tmux split: htop (left) | journalctl (right)
# Switch to other TTYs with Alt+F2 through Alt+F6 for normal login
{ config, pkgs, lib, ... }:

{
  # Never blank the screen
  boot.kernelParams = [ "consoleblank=0" ];

  # Auto-login jagadam97 on TTY1
  services.getty.autologinUser = "jagadam97";

  # Dashboard systemd service
  systemd.services.dashboard = {
    description = "TTY1 tmux dashboard (htop + journalctl)";

    # Start after TTY1 getty has set up the auto-login session
    after = [ "getty@tty1.service" "systemd-user-sessions.service" ];
    wants = [ "getty@tty1.service" ];

    # Run in the context of the logged-in user on TTY1
    serviceConfig = {
      Type = "simple";
      User = "jagadam97";
      PAMName = "login";
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";

      # Restart automatically if killed or exited
      Restart = "always";
      RestartSec = "2s";

      ExecStart = pkgs.writeShellScript "dashboard-start" ''
        # Kill any existing dashboard session
        ${pkgs.tmux}/bin/tmux kill-session -t dashboard 2>/dev/null || true

        # Create new tmux session on TTY1
        # Split vertically (side by side): left = htop, right = journalctl -f
        ${pkgs.tmux}/bin/tmux new-session -d -s dashboard -x "$(tput cols)" -y "$(tput lines)" \; \
          send-keys "${pkgs.htop}/bin/htop" Enter \; \
          split-window -h \; \
          send-keys "journalctl -f" Enter \; \
          select-pane -t 0

        # Attach to the session on this TTY
        exec ${pkgs.tmux}/bin/tmux attach-session -t dashboard
      '';
    };

    wantedBy = [ "multi-user.target" ];
  };
}
