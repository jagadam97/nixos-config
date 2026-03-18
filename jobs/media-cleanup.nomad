# Media cleanup job - replaces originals with converted files and fixes permissions
#
# Requires 16000 MHz CPU reservation so it only runs when encode jobs are done
# (encode jobs use 4000 MHz each, so 4 running = 16000 MHz consumed)
#
# Usage:
#   nomad job run jobs/media-cleanup.nomad
#
# It will:
#   1. Find all files in any "converted/" subdir under /mnt/hd4000/media
#   2. Move them over the original (replacing .mp4/.avi with .mkv too)
#   3. chmod 777 the replaced file
#   4. Remove the now-empty converted/ dir

job "media-cleanup" {
  datacenters = ["dc1"]
  type        = "batch"

  reschedule {
    attempts  = 0
    unlimited = false
  }

  group "cleanup" {
    count = 1

    task "replace-originals" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args    = ["-c", <<EOF
set -euo pipefail

echo "========================================"
echo " Media Cleanup - Replace with Converted"
echo "========================================"
echo " Scanning /mnt/hd4000/media for converted/ dirs..."
echo ""

REPLACED=0
FAILED=0
SKIPPED=0

find /mnt/hd4000/media -type f -path "*/converted/*.mkv" | sort | while read converted; do
  fname=$(basename "$converted")
  base="${fname%.*}"
  converted_dir=$(dirname "$converted")
  media_dir=$(dirname "$converted_dir")

  echo "----------------------------------------"
  echo "File    : $fname"
  echo "From    : $converted"

  # Find original - could be .mkv, .mp4, .avi, .mov, .ts etc
  original=$(find "$media_dir" -maxdepth 1 -type f \( \
    -iname "${base}.mkv" -o \
    -iname "${base}.mp4" -o \
    -iname "${base}.avi" -o \
    -iname "${base}.mov" -o \
    -iname "${base}.ts"  -o \
    -iname "${base}.wmv" \
  \) ! -path "*/converted/*" 2>/dev/null | head -1)

  if [ -z "$original" ]; then
    echo "  SKIP: no original found in $media_dir"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "  Replacing : $original"
  orig_size=$(du -sh "$original" | cut -f1)
  new_size=$(du -sh "$converted" | cut -f1)

  # Move converted over original location (always as .mkv)
  dest="$media_dir/$fname"
  mv "$converted" "$dest"
  chmod 777 "$dest" 2>/dev/null || true

  # Remove original if it had a different extension
  if [ "$original" != "$dest" ]; then
    rm -f "$original"
    echo "  Removed   : $original"
  fi

  echo "  Size      : $orig_size -> $new_size"
  REPLACED=$((REPLACED + 1))

  # Remove converted/ dir if now empty
  rmdir "$converted_dir" 2>/dev/null && echo "  Removed converted/ dir" || true
done

echo ""
echo "========================================"
echo " Done"
echo " Replaced : $REPLACED"
echo " Skipped  : $SKIPPED"
echo " Failed   : $FAILED"
echo "========================================"
EOF
        ]
      }

      env {
        PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      }

      resources {
        # 16000 MHz = almost all of the i5-8300H (18400 MHz total)
        # Nomad will only schedule this when encode jobs (4000 MHz each) are done
        cpu    = 16000
        memory = 512
      }
    }
  }
}
