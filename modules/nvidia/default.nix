# NVIDIA GTX 1050 Ti Mobile - PRIME offload configuration
# Intel iGPU handles display, NVIDIA handles compute (CUDA, ffmpeg hwaccel)
#
# TODO: After installation, find your PCI bus IDs with:
#   lspci | grep -E 'VGA|3D'
# Example output:
#   00:02.0 VGA compatible controller: Intel HD Graphics 630
#   01:00.0 3D controller: NVIDIA GTX 1050 Ti Mobile
# Then set intelBusId = "PCI:0:2:0" and nvidiaBusId = "PCI:1:0:0"
{ config, pkgs, lib, ... }:

{
  # Load NVIDIA proprietary drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Use proprietary driver (required for CUDA/NVENC)
    open = false;

    # Modesetting required for PRIME
    modesetting.enable = true;

    # Power management for laptops (helps with stability)
    powerManagement.enable = true;
    powerManagement.finegrained = false;

    # PRIME offload: Intel renders display, NVIDIA used on-demand for compute
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;  # provides `nvidia-offload` command
      };

      # TODO: Replace with actual PCI bus IDs from `lspci | grep -E 'VGA|3D'`
      # Format: "PCI:bus:device:function"
      intelBusId = "PCI:0:2:0";   # TODO: verify with lspci
      nvidiaBusId = "PCI:1:0:0";  # TODO: verify with lspci
    };
  };

  # OpenGL / hardware acceleration
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver   # VAAPI via NVIDIA (for ffmpeg hwaccel)
      vaapiVdpau            # VDPAU via VAAPI bridge
      libvdpau-va-gl        # VDPAU via OpenGL
    ];
  };

  # CUDA and compute packages
  environment.systemPackages = with pkgs; [
    # ffmpeg with NVIDIA hardware encoding/decoding (NVENC/NVDEC)
    (ffmpeg.override {
      withNvenc = true;
      withCuda = true;
    })

    # GPU monitoring tools
    nvtopPackages.nvidia
    cudaPackages.cuda_nvcc
  ];

  # Environment variables for NVIDIA offload
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };
}
