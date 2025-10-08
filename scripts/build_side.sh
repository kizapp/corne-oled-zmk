#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 left|right" >&2
  exit 1
fi

SIDE="$1"
case "$SIDE" in
  left)
    SHIELD="corne_left"
    BUILD_DIR="build/left"
    ;;
  right)
    SHIELD="corne_right"
    BUILD_DIR="build/right"
    ;;
  *)
    echo "Invalid side: $SIDE (use left or right)" >&2
    exit 1
    ;;
esac

echo "Removing .west ..."
rm -rf .west

echo "Removing build directory ..."
rm -rf build

echo "Building $SIDE (SHIELD=$SHIELD) ..."
docker run --rm -v "$PWD:/workdir" -w /workdir zmkfirmware/zmk-build-arm:stable bash -lc \
"west init -l config && west update && west zephyr-export && \
 west build -s zmk/app -b nice_nano_v2 -d $BUILD_DIR -S studio-rpc-usb-uart -- \
 -DSHIELD=$SHIELD -DZMK_CONFIG=/workdir/config -DCONFIG_ZMK_STUDIO=y"

UF2_SRC="$BUILD_DIR/zephyr/zmk.uf2"
echo "Build done. UF2: $UF2_SRC"

# Wait for UF2 bootloader volume and copy the firmware
echo "Put the $SIDE half into UF2 bootloader (double-tap BOOT). Waiting for mount..."

find_uf2_volume() {
  for vol in /Volumes/*; do
    [[ -d "$vol" ]] || continue
    if [[ -e "$vol/INFO_UF2.TXT" || -e "$vol/INDEX.HTM" ]]; then
      echo "$vol"
      return 0
    fi
    case "$(basename "$vol")" in
      NICENANO*|NRF52BOOT*|UF2*|NICE*|ADA*)
        echo "$vol"; return 0 ;;
    esac
  done
  return 1
}

UF2_VOL=""
for i in {1..120}; do
  if UF2_VOL="$(find_uf2_volume)"; then
    break
  fi
  sleep 1
done

if [[ -z "$UF2_VOL" ]]; then
  echo "Timeout: UF2 volume not found. Please enter bootloader and try again." >&2
  exit 1
fi

DEST_NAME="corne_${SIDE}-nice_nano_v2-zmk.uf2"
echo "Found UF2 volume at: $UF2_VOL"
echo "Copying $UF2_SRC -> $UF2_VOL/$DEST_NAME"
export COPYFILE_DISABLE=1  # macOS: do not write AppleDouble/extended attributes

copy_attempts=0
until cp -X "$UF2_SRC" "$UF2_VOL/$DEST_NAME"; do
  copy_attempts=$((copy_attempts+1))
  if [[ $copy_attempts -ge 5 ]]; then
    echo "Copy failed after $copy_attempts attempts. Try re-entering bootloader or granting Terminal Full Disk Access." >&2
    exit 1
  fi
  sleep 1
done

sync || true

echo "Done. The board should reboot automatically."
