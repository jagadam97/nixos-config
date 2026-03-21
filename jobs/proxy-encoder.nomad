# Proxy encoder job - NVENC H.264 720p proxy generation via ffmpeg
# Optimized for NixOS with GTX 1050 Ti Mobile
#
# Usage:
#   nomad job run jobs/proxy-encoder.nomad
#
#   nomad job dispatch \
#     -meta input="/mnt/hd4000/media/raw/foo.mkv" \
#     -meta output="/mnt/hd4000/media/proxies/foo_proxy.mp4" \
#     proxy-encoder
#
#   # Batch a folder:
#   for f in /mnt/hd4000/media/raw/*.mkv; do
#     name=$(basename "${f%.*}")
#     nomad job dispatch \
#       -meta input="$f" \
#       -meta output="/mnt/hd4000/media/proxies/${name}_proxy.mp4" \
#       proxy-encoder
#   done
#
# Monitor:
#   nomad job status proxy-encoder
#   nomad alloc logs -f <alloc-id>

job "proxy-encoder" {
  datacenters = ["dc1"]
  type        = "batch"

  meta {
    input  = ""
    output = ""
  }

  parameterized {
    meta_required = ["input", "output"]
  }

  group "transcode" {
    count = 1

    task "ffmpeg-proxy" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = ["-c", <<EOF
set -euo pipefail

INPUT="${NOMAD_META_input}"
OUTPUT="${NOMAD_META_output}"

echo "========================================"
echo " Proxy Encoder - NVENC H.264 720p"
echo "========================================"
echo " Input  : $INPUT"
echo " Output : $OUTPUT"
echo "========================================"

# Validate input exists
if [ ! -f "$INPUT" ]; then
  echo "ERROR: Input file not found: $INPUT"
  exit 1
fi

# Create output directory
mkdir -p "$(dirname "$OUTPUT")"
chmod 777 "$(dirname "$OUTPUT")" 2>/dev/null || true

# Get input info
INPUT_RES=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height \
  -of csv=s=x:p=0 "$INPUT" 2>/dev/null || echo "unknown")

echo "Input resolution : $INPUT_RES"
echo ""

# Try GPU encode with NVENC H.264
if ffmpeg -hide_banner \
    -hwaccel cuda \
    -hwaccel_output_format cuda \
    -i "$INPUT" \
    -vf scale_cuda=1280:720 \
    -c:v h264_nvenc \
    -preset fast \
    -profile:v main \
    -rc vbr \
    -cq 28 \
    -b:v 5M \
    -maxrate 8M \
    -bufsize 10M \
    -c:a aac \
    -b:a 128k \
    -ac 2 \
    -map_metadata 0 \
    -movflags +faststart \
    -map 0 \
    -y "$OUTPUT" 2>&1; then
  
  chmod 777 "$OUTPUT" 2>/dev/null || true
  ORIG_SIZE=$(du -sh "$INPUT" | cut -f1)
  NEW_SIZE=$(du -sh "$OUTPUT" | cut -f1)
  echo ""
  echo "========================================"
  echo " Done (GPU)"
  echo " Before : $ORIG_SIZE"
  echo " After  : $NEW_SIZE"
  echo "========================================"
else
  echo ""
  echo "GPU encode failed, trying CPU fallback..."
  ffmpeg -hide_banner \
    -i "$INPUT" \
    -vf "scale=1280:720" \
    -c:v libx264 \
    -preset medium \
    -profile:v main \
    -crf 23 \
    -c:a aac \
    -b:a 128k \
    -ac 2 \
    -map_metadata 0 \
    -movflags +faststart \
    -map 0 \
    -y "$OUTPUT" 2>&1
  
  chmod 777 "$OUTPUT" 2>/dev/null || true
  ORIG_SIZE=$(du -sh "$INPUT" | cut -f1)
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
        # Critical for NVENC on NixOS - provides CUDA/NVENC libraries
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/current-system/sw/lib"
      }

      resources {
        cpu    = 2000
        memory = 2048
      }

      kill_timeout = "30s"

      restart {
        attempts = 1
        interval = "5m"
        delay    = "10s"
        mode     = "fail"
      }
    }
  }
}
