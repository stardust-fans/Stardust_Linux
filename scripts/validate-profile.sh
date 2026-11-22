#!/usr/bin/env bash
#
# Static pre-flight checks that do not need root, Docker, or an Arch host.
# Run from Windows via WSL:
#   wsl -d archlinux -- bash scripts/validate-profile.sh
#
# YAML parsing is skipped if PyYAML is unavailable. The builder image installs
# PyYAML as a build dependency only for this convenience; Calamares itself has
# its own YAML parser.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${ROOT}/StardustArch"
FAIL=0

ok() { printf 'ok  %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

required=(
  "${ROOT}/build.sh"
  "${ROOT}/Dockerfile"
  "${ROOT}/user.conf"
  "${PROFILE}/profiledef.sh"
  "${PROFILE}/packages.x86_64"
  "${PROFILE}/packages.kde"
  "${PROFILE}/packages.desktop"
  "${PROFILE}/packages.speed"
  "${PROFILE}/pacman.conf"
  "${PROFILE}/airootfs/etc/os-release"
  "${PROFILE}/airootfs/etc/sddm.conf.d/autologin.conf"
  "${PROFILE}/airootfs/etc/calamares/settings.conf"
  "${PROFILE}/airootfs/etc/calamares/branding/stardustarch/branding.desc"
  "${PROFILE}/airootfs/etc/calamares/branding/stardustarch/stylesheet.qss"
  "${PROFILE}/airootfs/etc/calamares/branding/stardustarch/logo.png"
  "${PROFILE}/airootfs/etc/calamares/branding/stardustarch/wallpaper.jpg"
  "${PROFILE}/airootfs/etc/calamares/branding/stardustarch/calamares-wallpaper.jpg"
  "${PROFILE}/airootfs/usr/share/stardustarch/post-install-syu.sh"
  "${PROFILE}/airootfs/root/customize_airootfs.sh"
  "${ROOT}/pkg/calamares/PKGBUILD"
  "${ROOT}/pkg/stardustarch-calamares-config/PKGBUILD"
  "${ROOT}/scripts/container-build.sh"
)
for f in "${required[@]}"; do
  [[ -s "$f" ]] && ok "present ${f#${ROOT}/}" || bad "missing ${f#${ROOT}/}"
done

# Shell syntax
while IFS= read -r -d '' f; do
  if bash -n "$f" 2>/tmp/stardustarch-bashn.err; then
    : # ok
  else
    bad "bash -n ${f#${ROOT}/}: $(cat /tmp/stardustarch-bashn.err)"
  fi
done < <(find "${ROOT}" -type f \( -name '*.sh' -o -name 'PKGBUILD' \) -print0)
ok "all shell scripts and PKGBUILDs pass bash -n"

# Python syntax
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    if PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/stardustarch-pycache" python3 -m py_compile "$f"; then
      ok "py_compile ${f#${ROOT}/}"
    else
      bad "py_compile ${f#${ROOT}/}"
    fi
  done < <(find "${ROOT}" -type f -name '*.py' -print0)
else
  printf 'skip python3 not available\n'
fi

# No CRLF in text files. PNGs and other binaries are intentionally excluded.
if grep -rIl $'\r' "${ROOT}" --include='*.sh' --include='*.conf' --include='*.cfg' \
        --include='*.desc' --include='*.qml' --include='*.qss' --include='*.py' \
        --include='*.desktop' --include='PKGBUILD' --include='Dockerfile' >/tmp/stardustarch-crlf.txt 2>/dev/null; then
    if [[ -s /tmp/stardustarch-crlf.txt ]]; then
        bad "CRLF line endings in: $(tr '\n' ' ' < /tmp/stardustarch-crlf.txt)"
    fi
else
    ok "no CRLF in text files"
fi

# Branding/compliance checks
if grep -qi '^NAME="StardustArch"' "${PROFILE}/airootfs/etc/os-release" &&
   grep -qi 'derived from Arch Linux' "${PROFILE}/airootfs/etc/os-release"; then
    ok "os-release branding and derivation notice"
else
    bad "os-release must say StardustArch and derived from Arch Linux"
fi

if grep -q '^plasma-meta$' "${PROFILE}/packages.kde" &&
   ! grep -q '^kde-applications-meta$' "${PROFILE}/packages."* 2>/dev/null; then
    ok "plasma-meta only; no kde-applications-meta"
else
    bad "packages.kde must contain plasma-meta and never kde-applications-meta"
fi

if grep -q 'User=stardust' "${PROFILE}/airootfs/etc/sddm.conf.d/autologin.conf" &&
   grep -q 'autologin.conf' "${PROFILE}/airootfs/usr/share/stardustarch/post-install-syu.sh" &&
   grep -q 'autologin.conf' "${PROFILE}/airootfs/usr/share/stardustarch/target-cleanup.sh"; then
    ok "Live autologin is removed by both target cleanup phases"
else
    bad "Live autologin removal is not wired into both cleanup scripts"
fi

for needle in 'pacman-key --init' 'pacman-key --populate archlinux' 'pacman -Syu --noconfirm'; do
    if grep -Fq -- "$needle" "${PROFILE}/airootfs/usr/share/stardustarch/post-install-syu.sh"; then
        ok "post-install contains: ${needle}"
    else
        bad "post-install missing: ${needle}"
    fi
done

if { grep -vE '^[[:space:]]*#' "${PROFILE}/profiledef.sh" || true; } | grep -q 'nowatchdog' ||
   { grep -vE '^[[:space:]]*#' "${PROFILE}/profiledef.sh" || true; } | grep -q 'mitigations=off' ||
   { grep -vE '^[[:space:]]*#' "${PROFILE}/airootfs/etc/calamares/modules/bootloader.conf" || true; } | grep -q 'mitigations=off'; then
    bad "forbidden kernel speed hack present (nowatchdog or mitigations=off)"
else
    ok "no nowatchdog and no mitigations=off"
fi

if grep -q 'lsm=landlock,lockdown,yama,integrity,apparmor' "${PROFILE}/profiledef.sh"; then
    ok "explicit AppArmor LSM list in Live kernel parameters"
else
    bad "missing explicit lsm= AppArmor kernel parameter"
fi

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
    while IFS= read -r -d '' f; do
        if python3 - "$f" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as handle:
    list(yaml.safe_load_all(handle))
PY
        then
            :
        else
            bad "YAML parse ${f#${ROOT}/}"
        fi
    done < <(find "${PROFILE}/airootfs/etc/calamares" -type f \( -name '*.conf' -o -name '*.desc' \) -print0)
    ok "Calamares YAML files parse"
else
    printf 'skip PyYAML not importable; Calamares YAML parse not checked\n'
fi

# Critical customrepo package references.
for pkg in calamares stardustarch-calamares-config; do
    if grep -qx "$pkg" "${PROFILE}/packages.x86_64"; then
        ok "package list includes ${pkg}"
    else
        bad "package list missing ${pkg}"
    fi
done

# Default autologin file must only live in the Live image, never as a package
# source that would be installed twice.
if [[ ! -e "${ROOT}/pkg/stardustarch-calamares-config/files" ]]; then
    ok "no duplicate Calamares config tree in the package directory"
fi

if ((FAIL)); then
    printf '\n%d check(s) failed\n' "$FAIL" >&2
    exit 1
fi
printf '\nall static checks passed\n'
