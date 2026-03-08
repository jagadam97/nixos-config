# WireGuard VPN client
{ config, pkgs, lib, ... }:

{
  # SOPS secrets for WireGuard
  sops.secrets.wg_private_key = {};
  sops.secrets.wg_preshared_key = {};

  # RP filter settings for WireGuard
  networking.firewall.checkReversePath = lib.mkDefault "loose";

  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.10.10.4/24" ];
    listenPort = 51820;
    mtu = 1400;
    privateKeyFile = config.sops.secrets.wg_private_key.path;
    table = "off";

    peers = [{
      publicKey = "py9338My4lDz2GJPZDEtEVoAToLmTAGPE4WdJP349XY=";
      presharedKeyFile = config.sops.secrets.wg_preshared_key.path;
      endpoint = "152.70.69.235:51820";
      allowedIPs = [ "0.0.0.0/0" ];
      persistentKeepalive = 25;
    }];

    postUp = ''
      ip route add 10.10.10.0/24 dev wg0 || true
      ip route add default dev wg0 table 100 || true
      ip rule add from 10.10.10.4 table 100 || true
    '';

    preDown = ''
      ip rule del from 10.10.10.4 table 100 || true
      ip route del default dev wg0 table 100 || true
      ip route del 10.10.10.0/24 dev wg0 || true
    '';
  };

  # Kernel sysctl for WireGuard
  boot.kernel.sysctl = {
    "net.ipv4.conf.wg0.rp_filter" = 2;
  };
}
