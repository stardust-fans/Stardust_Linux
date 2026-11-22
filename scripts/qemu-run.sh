#!/usr/bin/env bash
#
# QEMU helper for StardustArch ISO smoke tests.
#
# Requires: qemu-system-x86, edk2-ovmf (UEFI mode only).
# On WSL2, /dev/kvm is often unavailable; the script falls back to TCG.
# TCG is functional but very slow and is not a performance benchmark.
#
# Usage:
#   ./scripts/qemu-run.sh [ISO] [uefi|bios]
#
# Optional:
#   STARDUST_DISK=/path/to/disk.qcow2  attach an install target disk
#   QEMU_DISPLAY=gtk|sdl|none          display backend (default gtk)
#   QEMU_MEM=6144                       memory in MiB
#
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-}"
MODE="${2:-uefi}"

if [[ -z "${ISO}" ]]; then
    ISO="$(find "${ROOT}/out" -maxdepth 1 -type f -name 'stardustarch-*.iso' -print -quit 2>/dev/null || true)"
fi
[[ -n "${ISO}" && -f "${ISO}" ]] || {
    printf 'usage: %s <iso> [uefi|bios]\n' "$0" >&2
    exit 1
}

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    printf 'qemu-system-x86_64 not found; install qemu-system-x86 and edk2-ovmf\n' >&2
    exit 1
}
[[ "${MODE}" == "uefi" || "${MODE}" == "bios" ]] || {
    printf 'mode must be uefi or bios\n' >&2
    exit 1
}

accel_args=()
cpu_args=(-cpu max)
if [[ -r /dev/kvm ]]; then
    accel_args=(-accel kvm)
    cpu_args=(-cpu host)
    printf 'qemu: using KVM\n' >&2
else
    accel_args=(-accel tcg,thread=multi)
    printf 'qemu: /dev/kvm unavailable, using TCG (slow; not a benchmark)\n' >&2
fi

display="${QEMU_DISPLAY:-gtk}"
mem="${QEMU_MEM:-6144}"
disk_args=()
if [[ -n "${STARDUST_DISK:-}" ]]; then
    [[ -f "${STARDUST_DISK}" ]] || {
        printf 'STARDUST_DISK does not exist: %s\n' "${STARDUST_DISK}" >&2
        exit 1
    }
    disk_args=(-drive "file=${STARDUST_DISK},if=virtio,format=qcow2")
fi

uefi_args=()
tmpvars=""
cleanup() {
    [[ -n "${tmpvars}" ]] && rm -f -- "${tmpvars}"
}
trap cleanup EXIT

if [[ "${MODE}" == "uefi" ]]; then
    ovmf_code=""
    for candidate in \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd \
        /usr/share/edk2/x64/OVMF_CODE.fd \
        /usr/share/ovmf/x64/OVMF_CODE.fd; do
        if [[ -f "${candidate}" ]]; then
            ovmf_code="${candidate}"
            break
        fi
    done
    [[ -n "${ovmf_code}" ]] || {
        printf 'OVMF firmware not found; install edk2-ovmf\n' >&2
        exit 1
    }
    ovmf_vars="${ovmf_code/OVMF_CODE/OVMF_VARS}"
    [[ -f "${ovmf_vars}" ]] || {
        printf 'OVMF vars template not found next to %s\n' "${ovmf_code}" >&2
        exit 1
    }
    tmpvars="$(mktemp /tmp/stardustarch-OVMF_VARS.XXXXXX.fd)"
    cp -- "${ovmf_vars}" "${tmpvars}"
    uefi_args=(
        -drive "if=pflash,format=raw,readonly=on,file=${ovmf_code}"
        -drive "if=pflash,format=raw,file=${tmpvars}"
    )
fi

exec qemu-system-x86_64 \
    -machine q35 \
    "${accel_args[@]}" \
    "${cpu_args[@]}" \
    -smp 4 \
    -m "${mem}" \
    "${uefi_args[@]}" \
    -device virtio-vga \
    -display "${display}" \
    -nic user,model=virtio-net-pci \
    -drive "file=${ISO},media=cdrom,readonly=on,format=raw" \
    "${disk_args[@]}" \
    -boot d
