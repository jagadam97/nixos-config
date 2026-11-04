# WireGuard VPN client
{ config, pkgs, lib, ... }:

{
  # SOPS secrets for WireGuard
  sops.secrets.wg_private_key = {};
  sops.secrets.wg_preshared_key = {};
  sops.secrets.wstunnel_env = {};

  # RP filter settings for WireGuard
  networking.firewall.checkReversePath = lib.mkDefault "loose";

  # Office network drops WireGuard data packets (handshakes pass), so tunnel
  # WG over WebSocket/TLS via NPM on the server. Server: wstunnel container
  # restricted to wg-easy:51820, NPM proxy host wg.jagadam97.uk -> wstunnel:8080.
  services.wstunnel = {
    enable = true;
    clients.wg = {
      connectTo = "wss://wg.jagadam97.uk:443";
      # WSTUNNEL_PREFIX, expanded by systemd in ExecStart
      environmentFile = config.sops.secrets.wstunnel_env.path;
      settings = {
        local-to-remote = [ "udp://127.0.0.1:51820:wg-easy:51820?timeout_sec=0" ];
        http-upgrade-path-prefix = "\${WSTUNNEL_PREFIX}";
      };
    };
  };

  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.10.10.3/24" ];
    mtu = 1280;
    privateKeyFile = config.sops.secrets.wg_private_key.path;
    table = "off";

    peers = [{
      publicKey = "Ksk6loxdeETWO/uTpWx9LuMr9kImA1BNQJvDHRfDQik=";
      presharedKeyFile = config.sops.secrets.wg_preshared_key.path;
      endpoint = "127.0.0.1:51820";
      allowedIPs = [ "10.10.10.0/24" "0.0.0.0/0" ];
      persistentKeepalive = 25;
    }];

    postUp = ''
      ip route add 10.10.10.0/24 dev wg0 || true
      ip route add default dev wg0 table 100 || true
      ip rule add from 10.10.10.3 table 100 || true
      # tailscaled marks its own sockets 0x80000; the office network resets
      # Tailscale control/DERP, so send that traffic out via wg0. Must sit
      # before tailscale's own fwmark rule at 5210.
      ip rule add fwmark 0x80000/0xff0000 table 100 priority 5200 || true
    '';

    preDown = ''
      ip rule del fwmark 0x80000/0xff0000 table 100 priority 5200 || true
      ip rule del from 10.10.10.3 table 100 || true
      ip route del default dev wg0 table 100 || true
      ip route del 10.10.10.0/24 dev wg0 || true
    '';
  };

  systemd.services.wg-quick-wg0 = {
    wants = [ "wstunnel-client-wg.service" ];
    after = [ "wstunnel-client-wg.service" ];
  };

  # Kernel sysctl for WireGuard
  boot.kernel.sysctl = {
    "net.ipv4.conf.wg0.rp_filter" = 2;
  };
}
