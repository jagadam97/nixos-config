# NVIDIA GTX 1050 Ti Mobile - PRIME offload configuration
# Intel iGPU handles display, NVIDIA handles compute (CUDA, ffmpeg hwaccel)
{
  config,
  pkgs,
  lib,
  ...
}:

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
    powerManagement.finegrained = true;

    # PRIME offload: Intel renders display, NVIDIA used on-demand for compute
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true; # provides `nvidia-offload` command
      };

      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # OpenGL / hardware acceleration
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver # VAAPI via NVIDIA (for ffmpeg hwaccel)
      libva-vdpau-driver # VDPAU via VAAPI bridge (formerly vaapiVdpau)
      libvdpau-va-gl # VDPAU via OpenGL
    ];
  };

  # CUDA and compute packages
  environment.systemPackages = with pkgs; [
    # ffmpeg-full includes NVENC/NVDEC and CUDA support out of the box
    ffmpeg-full

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
