ARG ARCH_IMAGE=archlinux:latest
FROM ${ARCH_IMAGE}

LABEL org.opencontainers.image.title="StardustArch ISO builder" \
      org.opencontainers.image.description="Ephemeral privileged Arch Linux builder for StardustArch" \
      org.opencontainers.image.licenses="MIT"

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Build dependencies:
#  - archiso: mkarchiso, pacstrap, xorriso integration
#  - base-devel: makepkg/fakeroot for the local calamares and paru-bin packages
#  - Qt6/KF6 deps: build Calamares 3.4.x from its pinned source tarball
#  - reflector: optional build-time mirror selection
RUN pacman -Syu --noconfirm --needed \
        archiso \
        base-devel \
        ccache \
        cmake \
        curl \
        dosfstools \
        extra-cmake-modules \
        git \
        hicolor-icon-theme \
        kcoreaddons \
        kpmcore \
        libglvnd \
        libisoburn \
        libpwquality \
        mtools \
        ninja \
        python \
        qt6-declarative \
        qt6-svg \
        qt6-tools \
        qt6-translations \
        reflector \
        rsync \
        squashfs-tools \
        syslinux \
        yaml-cpp \
        zstd \
    && pacman -Scc --noconfirm

RUN useradd --create-home --shell /bin/bash builder \
    && install -d -o builder -g builder \
        /var/cache/stardustarch/ccache \
        /var/cache/stardustarch/customrepo \
        /var/cache/stardustarch/srcdest \
        /var/cache/stardustarch/pacman/pkg

ENV CCACHE_DIR=/var/cache/stardustarch/ccache
ENV CCACHE_MAXSIZE=8G

VOLUME ["/var/cache/stardustarch"]
WORKDIR /src

# The entrypoint is deliberately bash; build.sh decides whether to run
# container-build.sh or open a debugging shell.
CMD ["/bin/bash"]
