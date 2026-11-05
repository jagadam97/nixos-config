# NetBird client (NetBird Cloud), running alongside Tailscale
{ config, lib, ... }:

{
  # Reusable setup key from app.netbird.io, one copy per host secrets.yaml
  sops.secrets.netbird_setup_key = {};

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
