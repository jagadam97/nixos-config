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

      # Node leaves the cluster cleanly on stop/interrupt instead of being
      # reaped as a dead peer. This host is BOTH server and client with
      # bootstrap_expect = 1, so on shutdown the single server leaves raft and
      # re-bootstraps on the next boot -- fine for a one-node cluster, but do
      # not copy this pair onto a multi-server cluster without thinking about
      # quorum.
      leave_on_terminate = true;
      leave_on_interrupt = true;

      client = {
        enabled = true;
        servers = [ "localhost" ];
        alloc_dir = "/tmp/nomad-allocs";

        # Drain allocations off this node before the agent exits, so jobs stop
        # gracefully rather than being killed with the process.
        drain_on_shutdown = {
          deadline = "5m"; # max time allowed to move all jobs off this node
          force = false; # respect job migration policies, no hard kill
          ignore_system_jobs = false; # keep system jobs up until service jobs finish
        };

        options = {
          "docker.privileged.enabled" = "true";
          "docker.volumes.enabled" = "true";
        };
      };

      plugin.raw_exec = {
        config = {
          enabled = true;
        };
      };

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
    # Must exceed client.drain_on_shutdown.deadline (5m) or systemd SIGKILLs
    # the agent mid-drain.
    TimeoutStopSec = "330s";
    # control-group, not mixed: the drain has to outlive the main process's
    # children, so systemd must not signal them early.
    KillMode = lib.mkForce "control-group";
    # Strip ALL systemd sandboxing so Nomad inherits the host mount namespace
    # and can see NFS mounts under /mnt
    PrivateMounts = lib.mkForce false;
    PrivateUsers = lib.mkForce false;
    PrivateTmp = lib.mkForce false;
    PrivateDevices = lib.mkForce false;
    ProtectSystem = lib.mkForce false;
    ProtectHome = lib.mkForce false;
    NoNewPrivileges = lib.mkForce false;
    RestrictNamespaces = lib.mkForce false;
    BindPaths = lib.mkForce [ ];
    BindReadOnlyPaths = lib.mkForce [ ];
  };

  environment.systemPackages = with pkgs; [
    nomad
    wander
  ];
}
