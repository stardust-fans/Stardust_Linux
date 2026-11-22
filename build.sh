#!/usr/bin/env bash
#
# StardustArch one-command ISO build launcher.
#
# Run this inside WSL2 (Arch is recommended) with Docker Desktop's WSL
# integration enabled. The build itself always happens in a disposable
# --privileged Arch container; the Windows/NTFS path is only bind-mounted
# read-only as source and as the final artifact destination.
#
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${ROOT}/StardustArch"
OUT="${ROOT}/out"
CACHEDIR="stardustarch-cache"
IMAGE="stardustarch-builder:latest"
ARCH_IMAGE="${ARCH_IMAGE:-archlinux:latest}"
CLEAN=0
SHELL_MODE=0
REBUILD_IMAGE=0

usage() {
    cat <<'EOF'
Usage: ./build.sh [options]

Options:
  --profile DIR    archiso profile directory (default: ./StardustArch)
  --out DIR        directory for the finished ISO and .sha256 (default: ./out)
  --cachedir NAME  persistent Docker volume for pacman/ccache/custom packages
                   (default: stardustarch-cache; must be a volume name, not a path)
  --clean          remove previous StardustArch ISO artifacts, then rebuild
  --rebuild-image  force a rebuild of the stardustarch-builder container image
  --shell          open an interactive root shell in the builder container
  -h, --help       show this help

Environment:
  ARCH_IMAGE       builder base image (default: archlinux:latest)
  DOCKER           docker executable (default: docker)
  STARDUST_FORCE_CALAMARES=1
                   rebuild Calamares even if a cached package exists

The container receives only:
  /src     project tree, read-only
  /out     artifact destination
  /var/cache/stardustarch    persistent Docker volume

All compilation, pacstrap, mkarchiso work directories, and temporary files
live under /tmp inside the container (container-local ext4, never NTFS/9P).
EOF
}

die() { printf 'build.sh: error: %s\n' "$*" >&2; exit 1; }
info() { printf 'build.sh: %s\n' "$*"; }

while (($#)); do
    case "$1" in
        --profile)
            [[ $# -ge 2 ]] || die "--profile needs a directory"
            PROFILE="$(realpath -m -- "$2")"
            shift 2
            ;;
        --out)
            [[ $# -ge 2 ]] || die "--out needs a directory"
            OUT="$(realpath -m -- "$2")"
            shift 2
            ;;
        --cachedir)
            [[ $# -ge 2 ]] || die "--cachedir needs a Docker volume name"
            CACHEDIR="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --rebuild-image)
            REBUILD_IMAGE=1
            shift
            ;;
        --shell)
            SHELL_MODE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1 (try --help)"
            ;;
    esac
done

[[ -r "${PROFILE}/profiledef.sh" ]] || die "profile not found: ${PROFILE}/profiledef.sh"
[[ -r "${ROOT}/Dockerfile" ]] || die "Dockerfile not found in ${ROOT}"
[[ -r "${ROOT}/user.conf" ]] || die "user.conf not found in ${ROOT}"

DOCKER="${DOCKER:-docker}"
command -v "${DOCKER}" >/dev/null 2>&1 || die "docker was not found. Enable Docker Desktop WSL integration, or in Arch WSL run: sudo pacman -S --needed docker docker-buildx && sudo systemctl enable --now docker"
"${DOCKER}" info >/dev/null 2>&1 || die "cannot talk to the Docker daemon. Start Docker Desktop with WSL integration, or run: sudo systemctl start docker"

# A Docker volume name, never a host directory. This keeps pacman/ccache off NTFS.
if [[ ! "${CACHEDIR}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    die "--cachedir must be a Docker volume name such as stardustarch-cache (host paths are rejected)"
fi
[[ "${CACHEDIR}" != "." && "${CACHEDIR}" != ".." ]] || die "invalid cachedir"

mkdir -p -- "${OUT}"
OUT="$(realpath -m -- "${OUT}")"
case "${OUT}" in
    /mnt/[a-zA-Z]/*)
        info "note: ${OUT} is on a Windows/9P mount; only the finished ISO is copied there. Build work stays in container /tmp."
        ;;
esac

info "profile : ${PROFILE}"
info "out     : ${OUT}"
info "cache   : Docker volume ${CACHEDIR}"
info "image   : ${IMAGE} (base ${ARCH_IMAGE})"

"${DOCKER}" volume inspect "${CACHEDIR}" >/dev/null 2>&1 || "${DOCKER}" volume create "${CACHEDIR}" >/dev/null
if ((REBUILD_IMAGE)) || ! "${DOCKER}" image inspect "${IMAGE}" >/dev/null 2>&1; then
    info "building builder image ${IMAGE}"
    "${DOCKER}" build \
        --build-arg "ARCH_IMAGE=${ARCH_IMAGE}" \
        -t "${IMAGE}" \
        -f "${ROOT}/Dockerfile" \
        "${ROOT}"
else
    info "using existing builder image ${IMAGE} (pass --rebuild-image to refresh)"
fi

profile_container="/src/StardustArch"
mount_args=(
    --mount "type=bind,src=${ROOT},dst=/src,readonly"
    --mount "type=bind,src=${OUT},dst=/out"
    --mount "type=volume,src=${CACHEDIR},dst=/var/cache/stardustarch"
)
if [[ "${PROFILE}" == "${ROOT}/"* ]]; then
    profile_container="/src/${PROFILE#"${ROOT}/"}"
else
    # Keep the promise of only mounting source and output: the profile is
    # source, so an out-of-tree profile gets its own read-only mount.
    mount_args+=(--mount "type=bind,src=${PROFILE},dst=/profile,readonly")
    profile_container="/profile"
fi

if ((SHELL_MODE)); then
    info "opening disposable privileged builder shell; /src, /out and cache are mounted"
    exec "${DOCKER}" run --rm -it --privileged \
        "${mount_args[@]}" \
        -e "STARDUST_PROFILE=${profile_container}" \
        -e "STARDUST_CLEAN=${CLEAN}" \
        -w /tmp \
        "${IMAGE}" /bin/bash
fi

info "starting disposable privileged build container"
set +e
"${DOCKER}" run --rm --privileged \
    "${mount_args[@]}" \
    -e "STARDUST_PROFILE=${profile_container}" \
    -e "STARDUST_CLEAN=${CLEAN}" \
    -e "STARDUST_FORCE_CALAMARES=${STARDUST_FORCE_CALAMARES:-0}" \
    -w /tmp \
    "${IMAGE}" /bin/bash /src/scripts/container-build.sh
rc=$?
set -e

if ((rc != 0)); then
    die "container build failed with exit code ${rc}"
fi
info "build completed"
ls -lh -- "${OUT}"/stardustarch-*.iso "${OUT}"/stardustarch-*.iso.sha256 2>/dev/null || true
