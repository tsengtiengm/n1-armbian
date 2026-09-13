#!/usr/bin/env bash
# Host-side helper: mount an Armbian image, chroot into its rootfs and run the
# customization script. Works natively on aarch64 runners; on x86_64 runners it
# transparently uses qemu-aarch64-static (binfmt must be registered).
#
# Usage: bash scripts/customize-image.sh <image.img> <install_msf:true|false> <profile:base|pentest>
set -euo pipefail

IMG="${1:?usage: customize-image.sh <image.img> <install_msf> <profile>}"
INSTALL_MSF="${2:-true}"
PROFILE="${3:-base}"
MNT=/mnt/n1root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -f "${IMG}" ]] || { echo "ERROR: image not found: ${IMG}"; exit 1; }

host_arch="$(uname -m)"
echo "[*] host arch: ${host_arch}"
if [[ "${host_arch}" != "aarch64" ]]; then
  command -v qemu-aarch64-static >/dev/null || {
    echo "ERROR: qemu-aarch64-static not available on this runner"; exit 1;
  }
fi

loop="$(sudo losetup -Pf --show "${IMG}")"
echo "[*] attached loop device: ${loop}"
lsblk "${loop}" || true

cleanup() {
  for d in dev/pts dev sys proc; do sudo umount -lf "${MNT}/${d}" 2>/dev/null || true; done
  sudo umount -lf "${MNT}" 2>/dev/null || true
  sudo losetup -d "${loop}" 2>/dev/null || true
}
trap cleanup EXIT

sudo mkdir -p "${MNT}"
sudo mount "${loop}p2" "${MNT}"

# --- resolver fix for chroot ---
# The image's /etc/resolv.conf may be a dangling symlink or a stale mount point,
# and its nsswitch.conf may reference systemd nss modules that are unusable in a
# plain chroot (observed: getaddrinfo EBUSY). Use the host's working resolver
# for the duration of the chroot, then restore the originals.
resolv_kind="none"
if sudo test -L "${MNT}/etc/resolv.conf"; then
  resolv_kind="symlink"
  resolv_target="$(sudo readlink "${MNT}/etc/resolv.conf")"
elif sudo test -f "${MNT}/etc/resolv.conf"; then
  resolv_kind="file"
  sudo cp "${MNT}/etc/resolv.conf" /tmp/n1-resolv.orig
fi
sudo umount "${MNT}/etc/resolv.conf" 2>/dev/null || true
sudo rm -f "${MNT}/etc/resolv.conf"
sudo cp /etc/resolv.conf "${MNT}/etc/resolv.conf"
if sudo test -f "${MNT}/etc/nsswitch.conf"; then
  sudo cp "${MNT}/etc/nsswitch.conf" /tmp/n1-nsswitch.orig
  sudo sed -i -E 's/^hosts:.*/hosts: files dns/' "${MNT}/etc/nsswitch.conf"
fi

for d in proc sys dev dev/pts; do sudo mount --bind "/${d}" "${MNT}/${d}"; done

if [[ "${host_arch}" != "aarch64" ]]; then
  sudo cp "$(command -v qemu-aarch64-static)" "${MNT}/usr/bin/"
  CHROOT_CMD=(sudo chroot "${MNT}" /usr/bin/qemu-aarch64-static /bin/bash)
else
  CHROOT_CMD=(sudo chroot "${MNT}" /bin/bash)
fi

sudo cp "${REPO_ROOT}/custom/customize-rootfs.sh" "${MNT}/tmp/customize-rootfs.sh"
"${CHROOT_CMD[@]}" /tmp/customize-rootfs.sh "${INSTALL_MSF}" "${PROFILE}" "${XRAY_ZIP_URL:-}" "${V2RAYA_DEB_URL:-}"

# --- restore original resolver config ---
if [[ "${host_arch}" != "aarch64" ]]; then
  sudo rm -f "${MNT}/usr/bin/qemu-aarch64-static"
fi
sudo rm -f "${MNT}/etc/resolv.conf"
case "${resolv_kind}" in
  symlink) sudo ln -sf "${resolv_target}" "${MNT}/etc/resolv.conf" ;;
  file)    sudo cp /tmp/n1-resolv.orig "${MNT}/etc/resolv.conf" ;;
esac
if sudo test -f /tmp/n1-nsswitch.orig; then
  sudo cp /tmp/n1-nsswitch.orig "${MNT}/etc/nsswitch.conf"
fi

sudo rm -f "${MNT}/tmp/customize-rootfs.sh"

echo "[+] image customized: ${IMG}"
