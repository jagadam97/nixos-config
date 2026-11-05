# NetBird client (NetBird Cloud), running alongside Tailscale
{ config, lib, ... }:

{
  # One-time setup key from app.netbird.io, per host in its secrets.yaml.
  # Only needed for first enrollment; peers log in with their own key after
  # netbird-login only runs at boot/unit change; re-run it when the key rotates
  sops.secrets.netbird_setup_key.restartUnits = [ "netbird-login.service" ];

  services.netbird.enable = true;

  services.netbird.clients.default = {
    # 51820 is taken on nauvoo by the wstunnel UDP listener for wg0
    port = 51830;
    login = {
      enable = true;
      setupKeyFile = config.sops.secrets.netbird_setup_key.path;
    };
  };

  # Same reason as wg0: asymmetric routes over wt0 trip strict rp_filter
  networking.firewall.checkReversePath = lib.mkDefault "loose";
}
