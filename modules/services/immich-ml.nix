# Immich machine-learning worker only.
#
# The server, postgres and redis stay on the Proxmox docker stack
# (jagadam97/Donnager, others/immich.yml). Only the ML worker runs here: it is
# stateless - no database, no redis, no access to the media library - and the
# server reaches it over plain HTTP via IMMICH_MACHINE_LEARNING_URL.
#
# The LXC side needs, in others/immich.yml:
#   - the immich_machine_learning service block deleted
#   - IMMICH_MACHINE_LEARNING_URL=http://192.168.4.200:3003 on immich_server
#
# Note this is the CPU-only build. The container it replaces was
# release-openvino on the LXC's Intel iGPU; nixpkgs ships no openvino or CUDA
# variant of immich-machine-learning, so the 1050 Ti sits idle here. To use it,
# this would have to become an oci-container running release-cuda.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.immich = {
    enable = true;

    # Both live on the LXC. Turning the database off also drops the
    # postgresql.target dependency the module would otherwise add.
    database.enable = false;
    redis.enable = false;

    machine-learning.enable = true;
    machine-learning.environment = {
      # The module pins IMMICH_HOST to "localhost" in its own config block
      # rather than as a default, so overriding needs mkForce or the two
      # definitions conflict.
      #
      # Bound to the static LAN address rather than all interfaces: the ML
      # endpoint has no authentication and this host runs with
      # networking.firewall.enable = false, so "" would expose inference to
      # anything that can route here, wireguard included.
      IMMICH_HOST = lib.mkForce "192.168.4.200";
      IMMICH_PORT = "3003";
      # Left at the module default of 1 worker on purpose: each one loads its
      # own copy of the models and this host has swapDevices = [ ].
    };
  };

  # The module has no per-service toggle - services.immich.enable = true always
  # defines the backend unit, and it would crash-loop here with no database.
  systemd.services.immich-server.enable = false;
}
