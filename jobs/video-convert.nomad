# Video converter job - H.265/HEVC using GPU (nvenc) via ffmpeg
#
# Usage:
#   nomad job run \
#     -var="input=/mnt/hd4000/media/movies/foo.mkv" \
#     -var="output=/mnt/hd4000/media/movies/converted/foo.mkv" \
#     -var="resolution=1080p" \
#     jobs/video-convert.nomad
#
# resolution options: 720p | 1080p | 4k | source
#   720p   -> scale to 1280x720,  CRF 26 (smallest file)
#   1080p  -> scale to 1920x1080, CRF 23
#   4k     -> scale to 3840x2160, CRF 20 (best quality)
#   source -> no scaling, just re-encode at CRF 23
#
# Audio: all tracks converted to AAC 192k
#
# Watch logs live:
#   nomad alloc logs -f <alloc-id>
# Or in Nomad UI: http://192.168.4.200:4646

variable "input" {
  type        = string
  description = "Full path to the input video file"
}

variable "output" {
  type        = string
  description = "Full path for the output file (should end in .mkv)"
}

variable "resolution" {
  type        = string
  description = "Target resolution: 720p | 1080p | 4k | source"
  default     = "1080p"
}

job "video-convert" {
  datacenters = ["dc1"]
  type        = "batch"

  reschedule {
    attempts  = 0
    unlimited = false
  }

  group "converter" {
    count = 1

    task "ffmpeg" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args    = ["-c", <<EOF
set -euo pipefail

INPUT="${var.input}"
OUTPUT="${var.output}"
RESOLUTION="${var.resolution}"

# Map resolution -> scale filter + CRF
case "$RESOLUTION" in
  720p)
    SCALE="scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos"
    CRF=26
    ;;
  1080p)
    SCALE="scale=1920:1080:force_original_aspect_ratio=decrease:flags=lanczos"
    CRF=23
    ;;
  4k)
    SCALE="scale=3840:2160:force_original_aspect_ratio=decrease:flags=lanczos"
    CRF=20
    ;;
  source)
    SCALE=""
    CRF=23
    ;;
  *)
    echo "ERROR: Invalid resolution '$RESOLUTION'. Must be one of: 720p, 1080p, 4k, source"
    exit 1
    ;;
esac

echo "========================================"
echo " Video Converter - H.265/HEVC (GPU)"
echo "========================================"
echo " Input      : $INPUT"
echo " Output     : $OUTPUT"
echo " Resolution : $RESOLUTION"
echo " CRF        : $CRF"
echo "========================================"
echo ""

# Validate input exists
if [ ! -f "$INPUT" ]; then
  echo "ERROR: Input file not found: $INPUT"
  exit 1
fi

# Create output directory as nobody to match NFS ownership
sudo -u nobody mkdir -p "$(dirname "$OUTPUT")"

# Check if already H.265
CODEC=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name \
  -of default=noprint_wrappers=1:nokey=1 "$INPUT" 2>/dev/null || echo "unknown")

# Get input resolution
INPUT_RES=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height \
  -of csv=s=x:p=0 "$INPUT" 2>/dev/null || echo "unknown")

echo "Input codec      : $CODEC"
echo "Input resolution : $INPUT_RES"

if [ "$CODEC" = "hevc" ] && [ "$RESOLUTION" = "source" ]; then
  echo "Input is already H.265/HEVC at source resolution, nothing to do."
  exit 0
fi

ORIG_SIZE=$(du -sh "$INPUT" | cut -f1)
echo "Input size       : $ORIG_SIZE"
echo ""

# Build scale filter arg (empty if source resolution)
if [ -n "$SCALE" ]; then
  VF_ARG="-vf $SCALE"
else
  VF_ARG=""
fi

# Try GPU (nvenc) first, fall back to CPU (libx265)
echo "Trying GPU encode (hevc_nvenc)..."
if sudo -u nobody ffmpeg -hide_banner \
    -hwaccel cuda -hwaccel_output_format cuda \
    -i "$INPUT" \
    $VF_ARG \
    -c:v hevc_nvenc \
    -preset p4 \
    -cq "$CRF" \
    -c:a aac -b:a 192k \
    -c:s copy \
    -map 0 \
    -y "$OUTPUT" 2>&1; then
  NEW_SIZE=$(du -sh "$OUTPUT" | cut -f1)
  echo ""
  echo "========================================"
  echo " Done (GPU)"
  echo " Resolution : $RESOLUTION"
  echo " Before     : $ORIG_SIZE"
  echo " After      : $NEW_SIZE"
  echo "========================================"
else
  echo ""
  echo "GPU encode failed, falling back to CPU (libx265)..."
  sudo -u nobody ffmpeg -hide_banner \
    -i "$INPUT" \
    $VF_ARG \
    -c:v libx265 \
    -crf "$CRF" \
    -preset medium \
    -c:a aac -b:a 192k \
    -c:s copy \
    -map 0 \
    -y "$OUTPUT" 2>&1
  NEW_SIZE=$(du -sh "$OUTPUT" | cut -f1)
  echo ""
  echo "========================================"
  echo " Done (CPU fallback)"
  echo " Resolution : $RESOLUTION"
  echo " Before     : $ORIG_SIZE"
  echo " After      : $NEW_SIZE"
  echo "========================================"
fi
EOF
        ]
      }

      env {
        PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      }

      resources {
        cpu    = 4000
        memory = 4096
      }
    }
  }
}
