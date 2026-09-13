#!/usr/bin/env bash
# Host-side helper: mount an Armbian image, chroot into its rootfs and run the
# customization script. Works natively on aarch64 runners; on x86_64 runners it
# transparently uses qemu-aarch64-static (binfmt must be registered).
#
# Usage: bash scripts/customize-image.sh <image.img> <install_msf:true|false>
set -euo pipefail

IMG="${1:?usage: customize-image.sh <image.img> <install_msf>}"
INSTALL_MSF="${2:-true}"
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

# resolv.conf inside the image is usually a symlink to systemd-resolved's stub;
# point it at a static resolver for the chroot and restore afterwards.
restore_resolv=0
if sudo test -L "${MNT}/etc/resolv.conf"; then
  resolv_target="$(sudo readlink "${MNT}/etc/resolv.conf")"
  echo "nameserver 8.8.8.8" | sudo tee "${MNT}/etc/resolv.conf" >/dev/null
  restore_resolv=1
fi

for d in proc sys dev dev/pts; do sudo mount --bind "/${d}" "${MNT}/${d}"; done

if [[ "${host_arch}" != "aarch64" ]]; then
  sudo cp "$(command -v qemu-aarch64-static)" "${MNT}/usr/bin/"
  CHROOT_CMD=(sudo chroot "${MNT}" /usr/bin/qemu-aarch64-static /bin/bash)
else
  CHROOT_CMD=(sudo chroot "${MNT}" /bin/bash)
fi

sudo cp "${REPO_ROOT}/custom/customize-rootfs.sh" "${MNT}/tmp/customize-rootfs.sh"
"${CHROOT_CMD[@]}" /tmp/customize-rootfs.sh "${INSTALL_MSF}"

sudo rm -f "${MNT}/tmp/customize-rootfs.sh"
if [[ "${host_arch}" != "aarch64" ]]; then
  sudo rm -f "${MNT}/usr/bin/qemu-aarch64-static"
fi
if [[ "${restore_resolv}" == "1" ]]; then
  sudo rm -f "${MNT}/etc/resolv.conf"
  sudo ln -sf "${resolv_target}" "${MNT}/etc/resolv.conf"
fi

echo "[+] image customized: ${IMG}"
