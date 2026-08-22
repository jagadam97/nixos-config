# Populate /boot/firmware for the Raspberry Pi 4.
#
# The SoC bootloader reads the FAT32 firmware partition, loads u-boot, and
# u-boot then reads /boot/extlinux/extlinux.conf from the ext4 /boot partition.
#
# nixos-hardware's raspberry-pi-4 module sets up the extlinux side but does not
# touch the firmware partition. sd-image-aarch64.nix does this via
# sdImage.populateFirmwareCommands, which we never run - so we do it here as an
# activation script instead. disko's image builder runs a real nixos-install,
# which runs activation, so this executes during the image build too.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  configTxt = pkgs.writeText "config.txt" ''
    kernel=u-boot.bin

    # Boot in 64-bit mode.
    arm_64bit=1

    # U-Boot needs this regardless of whether UART is actually used.
    enable_uart=1

    # Stop the firmware smashing the framebuffer set up by the mainline kernel
    # when it wants to show low-voltage or overtemperature warnings.
    avoid_warnings=1

    [pi4]
    enable_gic=1
    armstub=armstub8-gic.bin
    disable_overscan=1
    arm_boost=1
  '';

  # Pi 4 only. The upstream sd-image ships Pi 3 and Pi 5 files too; this host is
  # a Pi 4B Rev 1.5 and the rest would just be noise on a 512M partition.
  firmware = pkgs.runCommand "pella-rpi-firmware" { } ''
    mkdir -p $out
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bootcode.bin $out/
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/fixup*.dat $out/
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/start*.elf $out/
    cp ${pkgs.raspberrypifw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb $out/
    cp ${pkgs.ubootRaspberryPiAarch64}/u-boot.bin $out/u-boot.bin
    cp ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin $out/armstub8-gic.bin
    cp ${configTxt} $out/config.txt
  '';
in
{
  # rsync with -rt rather than -a: the target is vfat, which has no concept of
  # ownership or unix permissions, so -a produces a stream of warnings and
  # spurious diffs on every run.
  system.activationScripts.pellaRpiFirmware = {
    text = ''
      stamp=/boot/firmware/.pella-firmware
      if [ ! -e "$stamp" ] || [ "$(cat "$stamp")" != "${firmware}" ]; then
        echo "pella: populating /boot/firmware from ${firmware}"
        ${pkgs.rsync}/bin/rsync -rt --delete \
          --exclude='.pella-firmware' \
          ${firmware}/ /boot/firmware/
        echo "${firmware}" > "$stamp"
      fi
    '';
  };

  # Only the activation script needs rsync, but having it on PATH makes
  # debugging the firmware partition by hand much easier.
  environment.systemPackages = [ pkgs.rsync ];
}
