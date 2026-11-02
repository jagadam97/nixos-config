# WireGuard VPN client
{ config, pkgs, lib, ... }:

{
  # SOPS secrets for WireGuard
  sops.secrets.wg_private_key = {};
  sops.secrets.wg_preshared_key = {};

  # RP filter settings for WireGuard
  networking.firewall.checkReversePath = lib.mkDefault "loose";

  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.10.10.3/24" ];
    mtu = 1400;
    privateKeyFile = config.sops.secrets.wg_private_key.path;
    table = "off";

    peers = [{
      publicKey = "Ksk6loxdeETWO/uTpWx9LuMr9kImA1BNQJvDHRfDQik=";
      presharedKeyFile = config.sops.secrets.wg_preshared_key.path;
      endpoint = "80.225.254.197:51820";
      allowedIPs = [ "10.10.10.0/24" "0.0.0.0/0" ];
      persistentKeepalive = 25;
    }];

    postUp = ''
      ip route add 10.10.10.0/24 dev wg0 || true
      ip route add default dev wg0 table 100 || true
      ip rule add from 10.10.10.3 table 100 || true
    '';

    preDown = ''
      ip rule del from 10.10.10.3 table 100 || true
      ip route del default dev wg0 table 100 || true
      ip route del 10.10.10.0/24 dev wg0 || true
    '';
  };

  # Kernel sysctl for WireGuard
  boot.kernel.sysctl = {
    "net.ipv4.conf.wg0.rp_filter" = 2;
  };
}
