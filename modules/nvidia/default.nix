# NVIDIA GTX 1050 Ti Mobile - Headless server configuration
# For headless operation (no display), NVIDIA handles all compute (CUDA, NVENC, etc.)
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

    # Modesetting required for proper driver initialization
    modesetting.enable = true;

    # Power management - disable all sleep states for headless operation
    # This prevents the GPU from sleeping when lid is closed
    powerManagement.enable = false;
    powerManagement.finegrained = false;

    # Enable nvidia-settings utility
    nvidiaSettings = true;

    # NVIDIA persistence daemon - keeps GPU initialized even when no display attached
    # This is critical for headless/lid-closed operation
    nvidiaPersistenced = true;

    # No PRIME configuration for headless server - NVIDIA is the only GPU used
    # PRIME is for hybrid graphics laptops with displays
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
