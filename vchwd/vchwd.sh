#!/usr/bin/env bash
# vchwd-minimal: Автоустановка драйверов после установки Void Linux
set -euo pipefail

LOG="/var/log/vchwd-minimal.log"
log() { echo "[vchwd] $*" | tee -a "$LOG"; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Запусти от root: sudo ./vchwd-minimal.sh"; exit 1
  fi
}

need_root
log "Старт автоопределения оборудования..."

# --- CPU microcode ---
CPU_VENDOR="$(awk -F: '/vendor_id/ {print tolower($2)}' /proc/cpuinfo | head -n1 | sed 's/^[ \t]*//')"
case "$CPU_VENDOR" in
  *intel*)  CPU_UCODE="intel-ucode" ;;
  *amd*)    CPU_UCODE="amd-ucode" ;;
  *)        CPU_UCODE="" ;;
esac
log "CPU: $CPU_VENDOR → $CPU_UCODE"

# --- Kernel headers ---
KERNEL_VER="$(uname -r)"
KERNEL_FLAVOR="${KERNEL_VER#*-}"
PKG_HEADERS="linux${KERNEL_FLAVOR:+-$KERNEL_FLAVOR}-headers"
xbps-query -Rs "^$PKG_HEADERS$" >/dev/null || PKG_HEADERS="linux-headers"
log "Kernel headers: $PKG_HEADERS"

# --- GPU detection ---
GPU_INFO="$(lspci | grep -Ei 'vga|3d|display' || true)"
log "GPU: $GPU_INFO"

HAS_INTEL=0; HAS_NVIDIA=0; HAS_AMD=0
echo "$GPU_INFO" | grep -qi "intel"  && HAS_INTEL=1
echo "$GPU_INFO" | grep -qi "nvidia" && HAS_NVIDIA=1
echo "$GPU_INFO" | grep -qi "amd"    && HAS_AMD=1

# --- Build package list ---
PKGS=("linux-firmware" "$PKG_HEADERS")
[[ -n "$CPU_UCODE" ]] && PKGS+=("$CPU_UCODE")

if [[ "$HAS_NVIDIA" -eq 1 ]]; then
  PKGS+=("nvidia" "nvidia-libs" "nvidia-dkms")
elif [[ "$HAS_AMD" -eq 1 ]]; then
  PKGS+=("mesa-dri" "xf86-video-amdgpu")
elif [[ "$HAS_INTEL" -eq 1 ]]; then
  PKGS+=("mesa-dri" "xf86-video-intel")
fi

# --- Install ---
log "Установка: ${PKGS[*]}"
xbps-install -Sy ${PKGS[*]}

# --- Reconfigure ---
log "Пересборка initramfs..."
xbps-reconfigure -a

log "Готово. Перезагрузка рекомендуется."
