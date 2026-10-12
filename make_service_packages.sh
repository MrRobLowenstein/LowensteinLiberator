#!/bin/sh
#==============================================================================
# make_service_packages.sh
#
# Build two Loewenstein/Weinmann Prisma SD-update packages from a stock
# Update_weinmann_respiratory_device.zip:
#
#   phase1_servicemode  - installs, then drops the developer/service markers
#                         (/mnt/config/develop_servicesw_marker + develop_marker)
#                         so the device boots into the on-screen ServiceSW menu
#                         (where device type / serials / clock can be changed).
#   phase3_exitservice  - installs, then removes those markers so the device
#                         returns to normal therapy boot.
#
# Each output is a valid, md5-consistent package named exactly
# "Update_weinmann_respiratory_device.zip" (what the device looks for), with
# all files at the zip root and update.cks regenerated. Only postUpdate.sh is
# modified; every other file (and its md5) is carried over unchanged.
#
# Portable POSIX sh. Needs: unzip, zip, and md5sum (Linux) or md5 (macOS).
#
# Usage:  ./make_service_packages.sh <stock .zip> [output_dir]
#         output_dir defaults to ./service_packages
#==============================================================================

set -eu

SRC_ZIP="${1:-}"
OUTDIR="${2:-./service_packages}"
ZIPNAME="Update_weinmann_respiratory_device.zip"

usage() { echo "Usage: $0 <Update_weinmann_respiratory_device.zip> [output_dir]" >&2; exit 2; }
[ -n "$SRC_ZIP" ] || usage
[ -f "$SRC_ZIP" ] || { echo "error: input zip not found: $SRC_ZIP" >&2; exit 1; }

# --- required tools ---
command -v unzip >/dev/null 2>&1 || { echo "error: 'unzip' not found" >&2; exit 1; }
command -v zip   >/dev/null 2>&1 || { echo "error: 'zip' not found" >&2; exit 1; }

# md5 helper: md5sum (Linux/coreutils) or md5 -q (macOS/BSD)
if command -v md5sum >/dev/null 2>&1; then
    md5of() { md5sum "$1" | awk '{print $1}'; }
elif command -v md5 >/dev/null 2>&1; then
    md5of() { md5 -q "$1"; }
else
    echo "error: need 'md5sum' or 'md5'" >&2; exit 1
fi

# --- make SRC_ZIP and OUTDIR absolute (we cd around while zipping) ---
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd)" "$1" ;; esac; }
SRC_ZIP=$(abspath "$SRC_ZIP")
OUTDIR=$(abspath "$OUTDIR")
mkdir -p "$OUTDIR"

# --- temp workspace (auto-cleaned) ---
TMP=$(mktemp -d "${TMPDIR:-/tmp}/wmpkg.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

# Append the marker logic for the given mode (enter|exit) to postUpdate.sh.
append_marker_logic() {
    _work="$1"; _mode="$2"
    if [ "$_mode" = "enter" ]; then
        cat >> "$_work/postUpdate.sh" <<'EOF'

# --- custom: enter service mode on next boot (ServiceSW menu + USB console) ---
if mountpoint -q /mnt/config 2>/dev/null || mount | grep -q ' /mnt/config '; then
  touch /mnt/config/develop_servicesw_marker
  touch /mnt/config/develop_marker
  sync
  echo "custom: service-mode markers created"
fi
EOF
    else
        cat >> "$_work/postUpdate.sh" <<'EOF'

# --- custom: leave service mode / return to normal therapy boot ---
if mountpoint -q /mnt/config 2>/dev/null || mount | grep -q ' /mnt/config '; then
  rm -f /mnt/config/develop_servicesw_marker /mnt/config/develop_marker
  sync
  echo "custom: service-mode markers removed"
fi
EOF
    fi
}

# build_variant <label> <enter|exit>
build_variant() {
    label="$1"; mode="$2"
    work="$TMP/$label"
    mkdir -p "$work"

    # fresh extract of the stock package
    unzip -q -o "$SRC_ZIP" -d "$work"
    [ -f "$work/postUpdate.sh" ] || { echo "error: postUpdate.sh not in package" >&2; exit 1; }
    [ -f "$work/update.cks" ]    || { echo "error: update.cks not in package" >&2; exit 1; }

    # modify only postUpdate.sh
    append_marker_logic "$work" "$mode"

    # regenerate update.cks, preserving the original file list & order
    newcks="$work/update.cks.new"
    : > "$newcks"
    # read "<md5> <name>"; keep original name (handles possible trailing no-newline)
    while read -r oldmd5 name || [ -n "$oldmd5" ]; do
        [ -n "${name:-}" ] || continue
        [ -f "$work/$name" ] || { echo "error: file listed in manifest is missing: $name" >&2; exit 1; }
        printf '%s %s\n' "$(md5of "$work/$name")" "$name" >> "$newcks"
    done < "$work/update.cks"
    mv "$newcks" "$work/update.cks"

    # assemble the output zip (files at root): update.cks + every file it lists
    outsub="$OUTDIR/$label"
    mkdir -p "$outsub"
    out="$outsub/$ZIPNAME"
    rm -f "$out"
    (
        cd "$work"
        set -- update.cks
        while read -r _m n || [ -n "$_m" ]; do [ -n "${n:-}" ] && set -- "$@" "$n"; done < update.cks
        zip -X -q "$out" "$@"
    )

    # verify: extract the built zip and re-check every md5 against its manifest
    vdir="$TMP/verify_$label"
    mkdir -p "$vdir"
    unzip -q -o "$out" -d "$vdir"
    ok=1
    while read -r m n || [ -n "$m" ]; do
        [ -n "${n:-}" ] || continue
        c=$(md5of "$vdir/$n")
        [ "$m" = "$c" ] || { echo "  VERIFY FAIL: $n manifest=$m calc=$c" >&2; ok=0; }
    done < "$vdir/update.cks"
    [ "$ok" = 1 ] || { echo "error: md5 verification failed for $label" >&2; exit 1; }

    echo "  $label -> $out  (verified OK)"
}

echo "Source : $SRC_ZIP"
echo "Output : $OUTDIR"
echo "Building packages..."
build_variant "phase1_servicemode" "enter"
build_variant "phase3_exitservice" "exit"
echo "Done."
echo
echo "Put the chosen zip on a FAT32 SD card at its ROOT (keep the exact name),"
echo "install it on the device (do NOT cut power), then remove the SD card."
echo "  phase1_servicemode -> enters the on-screen ServiceSW menu"
echo "  phase3_exitservice -> returns to normal therapy boot"
