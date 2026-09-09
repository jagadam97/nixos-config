# HashiCorp Consul - single-node server for local testing
{ config, pkgs, lib, ... }:

{
  services.consul = {
    enable = true;
    package = pkgs.consul;
    webUi = true;

    extraConfig = {
      datacenter = "dc1";
      data_dir = "/var/lib/consul";

      server = true;
      bootstrap_expect = 1;

      # Single node: gossip/RPC stay on loopback, HTTP/DNS listen on all
      # interfaces so the UI is reachable from the LAN.
      bind_addr = "127.0.0.1";
      client_addr = "0.0.0.0";

      ports = {
        http = 8500;
        dns = 8600;
      };

      telemetry = {
        prometheus_retention_time = "60s";
        disable_hostname = true;
      };

      # Local testing only - no ACLs, no TLS, no gossip encryption.
      connect = {
        enabled = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    consul
  ];
}
