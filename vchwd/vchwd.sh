#!/usr/bin/env bash
# vchwd: Void Linux hardware autodetect & setup (NVIDIA-first)
# Author: Igor + Copilot crew
set -euo pipefail

LOG_FILE="/var/log/vchwd.log"
DRY_RUN=0

log() { echo "[vchwd] $*" | tee -a "$LOG_FILE"; }
run() { if [[ "$DRY_RUN" -eq 1 ]]; then log "DRY: $*"; else log "RUN: $*"; eval "$@"; fi; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo ./vchwd.sh)"; exit 1
  fi
}

usage() {
  cat <<EOF
vchwd: NVIDIA-first hardware setup for Void Linux

Usage:
  sudo ./vchwd.sh [--dry-run]

Options:
  --dry-run   Show actions without changing system
EOF
}

while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

need_root
run "touch $LOG_FILE"

# --- Package maps ---
PKG_INTEL_UCODE="intel-ucode"
PKG_AMD_UCODE="amd-ucode"
PKG_FIRMWARE=("linux-firmware")
PKG_XORG=("xorg-server" "xorg-xinit")
PKG_NVIDIA=("nvidia" "nvidia-libs" "nvidia-dkms")

# Detect CPU vendor
CPU_VENDOR="$(awk -F: '/vendor_id/ {print tolower($2)}' /proc/cpuinfo | head -n1 | sed 's/^[ \t]*//')"
log "CPU vendor: $CPU_VENDOR"
case "$CPU_VENDOR" in
  *intel*)  CPU_UCODE="$PKG_INTEL_UCODE" ;;
  *amd*)    CPU_UCODE="$PKG_AMD_UCODE" ;;
  *)        CPU_UCODE="" ;;
esac

# Detect GPUs
GPU_LINES="$(lspci -nn | egrep -i 'vga|3d|display')"
log "GPUs detected: $GPU_LINES"

HAS_INTEL=0; HAS_NVIDIA=0
echo "$GPU_LINES" | grep -qi "intel" && HAS_INTEL=1
echo "$GPU_LINES" | grep -qi "nvidia" && HAS_NVIDIA=1

# --- Menu selection ---
echo "Выбери профиль установки:"
echo "  1) NVIDIA-only (десктоп)"
echo "  2) Hybrid PRIME (ноут Intel+NVIDIA)"
echo "  3) Intel-only fallback"
read -rp "Твой выбор [1-3]: " PROFILE

case "$PROFILE" in
  1) GEN_MODE="nvidia" ;;
  2) GEN_MODE="prime" ;;
  3) GEN_MODE="intel" ;;
  *) echo "Неверный выбор, выходим."; exit 1 ;;
esac
log "Выбран режим: $GEN_MODE"

# --- Build package list ---
INSTALL_PKGS=("${PKG_XORG[@]}" "${PKG_FIRMWARE[@]}")
[[ -n "$CPU_UCODE" ]] && INSTALL_PKGS+=("$CPU_UCODE")

if [[ "$GEN_MODE" == "nvidia" || "$GEN_MODE" == "prime" ]]; then
  INSTALL_PKGS+=("${PKG_NVIDIA[@]}")
fi

# Deduplicate
mapfile -t INSTALL_PKGS < <(printf "%s\n" "${INSTALL_PKGS[@]}" | awk '!seen[$0]++')

log "Packages to install: ${INSTALL_PKGS[*]}"
run "xbps-install -Sy ${INSTALL_PKGS[*]}"

# --- Generate configs ---
mkdir -p /etc/X11/xorg.conf.d

if [[ "$GEN_MODE" == "nvidia" ]]; then
  CONF="/etc/X11/xorg.conf.d/10-nvidia.conf"
  cat > "$CONF" <<'CONF'
Section "Device"
  Identifier "NVIDIA"
  Driver "nvidia"
  Option "AllowEmptyInitialConfiguration" "true"
EndSection
CONF
  log "Wrote $CONF"
fi

if [[ "$GEN_MODE" == "prime" ]]; then
  CONF="/etc/X11/xorg.conf.d/20-prime.conf"
  INTEL_BUSID=$(lspci | grep -i 'vga.*intel' | awk '{print $1}' | sed 's/:/ /g' | awk '{printf "PCI:%d:%d:%d\n","0x"$1,"0x"$2,"0x"$3}')
  NVIDIA_BUSID=$(lspci | grep -i 'vga.*nvidia' | awk '{print $1}' | sed 's/:/ /g' | awk '{printf "PCI:%d:%d:%d\n","0x"$1,"0x"$2,"0x"$3}')
  cat > "$CONF" <<CONF
Section "ServerLayout"
    Identifier "layout"
    Screen 0 "iGPU"
EndSection

Section "Device"
    Identifier "iGPU"
    Driver "modesetting"
    BusID "$INTEL_BUSID"
EndSection

Section "Device"
    Identifier "dGPU"
    Driver "nvidia"
    BusID "$NVIDIA_BUSID"
    Option "AllowEmptyInitialConfiguration"
EndSection
CONF
  log "Wrote $CONF"

  # prime-run helper
  cat > /usr/local/bin/prime-run <<'SCRIPT'
#!/bin/sh
__NV_PRIME_RENDER_OFFLOAD=1 \
__GLX_VENDOR_LIBRARY_NAME=nvidia \
__VK_LAYER_NV_optimus=NVIDIA_only \
exec "$@"
SCRIPT
  chmod +x /usr/local/bin/prime-run
  log "Installed /usr/local/bin/prime-run"
fi

# --- Rebuild initramfs ---
log "Rebuilding initramfs"
run "xbps-reconfigure -a"

log "vchwd completed. Reboot recommended."
