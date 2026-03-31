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
    # Disable finegrained power management to prevent GPU from sleeping when lid closed
    powerManagement.enable = false;
    powerManagement.finegrained = false;

    # Force the NVIDIA GPU to stay on - critical for headless/server operation
    nvidiaSettings = true;

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

  # NVIDIA persistence daemon - keeps GPU initialized even when no display
  # This is crucial for headless/lid-closed operation
  hardware.nvidia.nvidiaPersistenced = true;

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

  # NVIDIA persistence daemon is already enabled above (nvidiaPersistenced = true)
  # This keeps the driver loaded even without a display attached
  # The nvidia-persistenced service already enables persistence mode when it starts

  # Kernel parameters to prevent GPU from sleeping on lid close
  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    # Prevent ACPI sleep on NVIDIA GPU
    "acpi_sleep=nonvs"
  ];
}
