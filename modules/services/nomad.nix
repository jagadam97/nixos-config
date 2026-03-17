# HashiCorp Nomad
{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.nomad = {
    enable = true;
    package = pkgs.nomad;

    settings = {
      datacenter = "dc1";
      data_dir = "/var/lib/nomad";

      server = {
        enabled = true;
        bootstrap_expect = 1;
      };

      client = {
        enabled = true;
        servers = [ "localhost" ];
        alloc_dir = "/tmp/nomad-allocs";

        options = {
          "docker.privileged.enabled" = "true";
          "docker.volumes.enabled" = "true";
        };
      };

      plugin.raw_exec.config.enabled = true;

      plugin.docker = {
        config = {
          allow_privileged = true;
          volumes = {
            enabled = true;
          };
        };
      };

      consul = {
        address = "localhost:8500";
      };

      vault = {
        enabled = false;
      };

      telemetry = {
        publish_allocation_metrics = true;
        publish_node_metrics = true;
        prometheus_metrics = true;
      };

      ui = {
        enabled = true;
      };

      ports = {
        http = 4646;
        rpc = 4647;
        serf = 4648;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /tmp/nomad-allocs    0777 root root -"
    "d /var/lib/alloc_mounts 0777 root root -"
  ];

  systemd.services.nomad.serviceConfig = {
    ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p /tmp/nomad-allocs /var/lib/alloc_mounts";
    # Give Nomad time to drain running jobs before systemd force-kills it
    TimeoutStopSec = "120s";
    KillMode = lib.mkForce "mixed";
    # Allow Nomad tasks to access NFS mounts from the host mount namespace
    PrivateMounts = lib.mkForce false;
    # Bind /mnt into the service namespace explicitly
    BindPaths = [ "/mnt" ];
  };

  environment.systemPackages = with pkgs; [
    nomad
  ];
}
