# Video converter job - H.265/HEVC using GPU (nvenc) via ffmpeg
#
# Usage:
#   nomad job run \
#     -var="input=/mnt/hd4000/media/movies/foo.mkv" \
#     -var="output=/mnt/hd4000/media/movies/converted/foo.mkv" \
#     jobs/video-convert.nomad
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

variable "crf" {
  type        = string
  description = "Quality: lower = better quality, larger file (18-28 recommended)"
  default     = "23"
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
CRF="${var.crf}"

echo "========================================"
echo " Video Converter - H.265/HEVC (GPU)"
echo "========================================"
echo " Input  : $INPUT"
echo " Output : $OUTPUT"
echo " CRF    : $CRF"
echo "========================================"
echo ""

# Validate input exists
if [ ! -f "$INPUT" ]; then
  echo "ERROR: Input file not found: $INPUT"
  exit 1
fi

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT")"

# Check if already H.265
CODEC=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name \
  -of default=noprint_wrappers=1:nokey=1 "$INPUT" 2>/dev/null || echo "unknown")

echo "Input codec : $CODEC"

if [ "$CODEC" = "hevc" ]; then
  echo "Input is already H.265/HEVC, nothing to do."
  exit 0
fi

ORIG_SIZE=$(du -sh "$INPUT" | cut -f1)
echo "Input size  : $ORIG_SIZE"
echo ""

# Try GPU (nvenc) first, fall back to CPU (libx265)
echo "Trying GPU encode (hevc_nvenc)..."
if ffmpeg -hide_banner \
    -hwaccel cuda -hwaccel_output_format cuda \
    -i "$INPUT" \
    -c:v hevc_nvenc \
    -preset p4 \
    -cq "$CRF" \
    -c:a copy \
    -c:s copy \
    -map 0 \
    -y "$OUTPUT" 2>&1; then
  NEW_SIZE=$(du -sh "$OUTPUT" | cut -f1)
  echo ""
  echo "========================================"
  echo " Done (GPU)"
  echo " Before : $ORIG_SIZE"
  echo " After  : $NEW_SIZE"
  echo "========================================"
else
  echo ""
  echo "GPU encode failed, falling back to CPU (libx265)..."
  ffmpeg -hide_banner \
    -i "$INPUT" \
    -c:v libx265 \
    -crf "$CRF" \
    -preset medium \
    -c:a copy \
    -c:s copy \
    -map 0 \
    -y "$OUTPUT" 2>&1
  NEW_SIZE=$(du -sh "$OUTPUT" | cut -f1)
  echo ""
  echo "========================================"
  echo " Done (CPU fallback)"
  echo " Before : $ORIG_SIZE"
  echo " After  : $NEW_SIZE"
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
