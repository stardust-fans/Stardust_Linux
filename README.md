# StardustArch

> 装完即可日用、默认 KDE Plasma、为启动和响应速度做过取舍的 Arch Linux 衍生发行版。
> **基于 / derived from Arch Linux，不是 Arch Linux，也不代表 Arch Linux 官方。**

源码仓库：<https://github.com/stardust-fans/Stardust_Linux>

> 仓库只提交源码与压缩后的壁纸成品（`wallpaper.jpg`、`calamares-wallpaper.jpg`）。
> 67 MB 的 `bg.png` 原图、ISO 和 `.pkg.tar.zst` 不进入 Git；ISO 通过 Releases 发布。

本文档是交付说明、构建手册、验收清单和回滚手册。所有代码、配置、脚本均为英文；文档为中文。

---

## 一页速览

### 定位

| 项目 | 内容 |
|---|---|
| 名称 | **StardustArch** |
| 上游 | Arch Linux（`ID_LIKE=arch`，`/etc/os-release` 明示 derived from） |
| 桌面 | KDE Plasma，唯一桌面 meta 包 `plasma-meta` |
| 显示管理器 | SDDM，Plasma Wayland 会话；SDDM 自身使用 X11 greeter（因此安装 `xorg-server`） |
| 主安装器 | Calamares（Live 桌面一键启动 + 自动启动） |
| 后备安装器 | `archinstall`（仅保留在 Live ISO） |
| 默认交换 | zram（zram-generator）；不建磁盘 swap；休眠需用户自建 swapfile |
| 默认文件系统 | ext4 + `noatime,lazytime`；可选 btrfs + `compress=zstd:1` |
| 目标 | 首次启动即进入 Plasma；中文显示/输入、网络、声音、时间同步可用 |

### 与官方 Arch ISO 的差异

1. **图形安装器是主流程**：官方 Arch ISO 默认 `archinstall`；StardustArch 预装并自动启动 Calamares。`archinstall` 仍保留作为后备。
2. **Live 直接进 Plasma**：SDDM 自动登录 `stardust`，密码为空，sudo 免密；这些**只存在于 Live**，安装后被删除。
3. **桌面预装**：`plasma-meta` + SDDM + PipeWire + NetworkManager + Noto CJK + fcitx5/rime；日用软件单独放在 `packages.desktop`，可整体关闭。
4. **装完自动完整升级**：Calamares 在 `unpackfs + mount` 之后、`finished` 之前，在 `arch-chroot` 里执行 `pacman-key --init`、`pacman-key --populate archlinux`、`pacman -Syu --noconfirm`，日志落到目标 `/var/log/stardustarch-postinstall.log`。
5. **可为安装时选择国内仓库**：Calamares 增加 “Repositories” 页，可勾选国内 Arch 镜像和/或 archlinuxcn 仓库；不选也能正常安装。
6. **Calamares 不在 Arch 官方仓库**：本项目提供固定版本的本地 PKGBUILD（AUR 3.4.2 改）和 `stardustarch-calamares-config` 包，通过 `[customrepo]` 安装。**这是与官方 ISO 最大的构建差异，也是首次构建耗时的主要来源。**
7. **速度取舍写进配置**：squashfs/initramfs zstd、精简 archiso hooks、不启用无用服务、zram、KWin 模糊关闭、Baloo 关闭、动画时长减半。**不添加 `nowatchdog`，不添加 `mitigations=off`。**
8. **品牌合规**：自有星尘/轨道 Logo，不复用 Arch 官方 Logo；Calamares 壁纸由用户提供的 `bg.png` 转换而来；`os-release` 写明 derived from Arch Linux，不宣称自己是 Arch Linux。

### 三大提速抓手

1. **压缩与构建 I/O**
   - Live 根文件系统 squashfs 用 **zstd**（`profiledef.sh`），冷启动解压显著快于 xz。
   - initramfs 用 **zstd**，并删除 PXE 相关 archiso hooks。
   - 构建期 `ParallelDownloads = 20`、`reflector` 国内镜像、`ccache`、持久化 Docker volume、Calamares 只编译一次并缓存为本地包。
2. **启动链精简**
   - 不启用 `NetworkManager-wait-online`。
   - 只启用 SDDM、NetworkManager、systemd-timesyncd、fstrim、AppArmor、蓝牙、power-profiles-daemon。
   - zram 替代磁盘 swap；`vm.swappiness=180`、`vm.page-cluster=0`。
   - 明确**不使用** `nowatchdog`、`mitigations=off` 这类以安全换速度的参数。
3. **桌面运行期**
   - 桌面只装 `plasma-meta`，不用 `kde-applications-meta` 叠加。
   - KWin 模糊/对比度效果关闭；Baloo 文件索引关闭；Plasma 动画时长 0.5×。
   - 日用软件（Firefox、Konsole、Dolphin、Kate 等）独立成组，可关闭而不动桌面。

### 构建耗时与体积预估

| 阶段 | 预估 | 说明 |
|---|---:|---|
| 首次 `docker build` 构建器镜像 | 5–15 分钟 | 下载 `archlinux:latest` 与 Qt6/archiso 依赖 |
| 首次编译 Calamares 3.4.2 | 10–30 分钟 | 8 核；之后从 Docker volume 复用 |
| 首次构建 ISO | 15–40 分钟 | 取决于镜像、CPU、是否首次下载 Plasma/字体 |
| 后续增量构建 | 8–25 分钟 | Calamares 包复用，pacman cache 复用 |
| ISO 体积 | **约 2.3–3.2 GiB** | zstd squashfs + KDE + 字体；未实测，属按包集估算 |
| 安装后占用 | 约 7–10 GiB | 未计用户数据和浏览器缓存 |

> 以上为估算，不是实测。当前交付环境没有可用的 Docker CLI/Daemon，因此**未实际生成 ISO**；静态检查结果见文末“验证状态”。

---

## 目录结构

```
StardustArch/
├── build.sh                         # 一键构建入口（在 WSL2 里运行）
├── Dockerfile                       # 临时 Arch 构建器
├── .dockerignore
├── user.conf                        # 唯一构建选项入口（英文）
├── README.md
├── scripts/
│   ├── container-build.sh           # 在容器内组装 profile / customrepo / ISO
│   ├── validate-profile.sh          # 无 root 静态自检
│   ├── qemu-run.sh                  # QEMU 启动辅助
│   └── make-branding-assets.ps1     # 重新生成自有品牌图（Windows）
├── pkg/
│   ├── calamares/PKGBUILD           # 3.4.2，INSTALL_CONFIG=OFF，保留 packagechooser
│   ├── stardustarch-calamares-config/PKGBUILD
│   └── paru-bin/PKGBUILD            # INSTALL_PARU=yes 时使用
├── StardustArch/
│   ├── profiledef.sh
│   ├── packages.x86_64
│   ├── packages.kde                 # 只含 plasma-meta + 最小配套
│   ├── packages.desktop             # 日用软件，注释开关
│   ├── packages.speed               # 提速包
│   ├── pacman.conf                  # 构建期，[customrepo] 置顶
│   ├── syslinux/                    # BIOS 启动
│   ├── efiboot/                     # UEFI systemd-boot
│   └── airootfs/
│       ├── etc/os-release
│       ├── etc/sddm.conf.d/autologin.conf
│       ├── etc/calamares/
│       │   ├── settings.conf
│       │   ├── modules/
│       │   └── branding/stardustarch/
│       ├── etc/skel/...
│       ├── usr/share/stardustarch/post-install-syu.sh
│       ├── usr/share/stardustarch/target-cleanup.sh
│       └── root/customize_airootfs.sh
└── out/                             # 构建产物（运行时创建）
```

> `airootfs/etc/calamares/` 是**权威源文件**。构建脚本会把它、Live 脚本、启动器和 Python 模块打包成 `stardustarch-calamares-config`，然后从 airootfs 中移除同名路径，确保 `/etc/calamares` 只有包一个所有者，避免 pacman 文件冲突和手工拷贝。

---

## 构建环境（按要求固定）

- Windows 10/11 + WSL2；
- Docker Desktop，WSL2 后端；
- **在 Arch Linux WSL2 里运行** `build.sh`（把 Docker Desktop 的 WSL Integration 打开给该发行版）；
- 临时容器：`archlinux:latest`，`--privileged`，`--rm`；
- 容器只挂载：
  - 项目源码 `/src`（只读；profile 和工作脚本都在这里）；
  - `out/`（成品 ISO 和 sha256 的输出）；
  - Docker volume `/var/cache/stardustarch`（pacman、ccache、Calamares 本地包）。
- 所有实际编译、pacstrap、mkarchiso 工作目录在容器 `/tmp/stardustarch`，即容器本地 ext4；**不放在 `/mnt/c`、`/mnt/f` 或任何 NTFS/9P 路径**。

### 首次准备

```bash
# 在 Windows PowerShell 中确认 WSL 发行版
wsl -l -v

# 进入 Arch WSL（名称按实际修改）
wsl -d archlinux

# 确认 Docker Desktop 的 WSL Integration 已启用
docker version
```

### 一键构建

```bash
cd /path/to/StardustArch
chmod +x build.sh scripts/*.sh
./build.sh
```

默认参数等价于：

```bash
./build.sh --profile ./StardustArch --out ./out --cachedir stardustarch-cache
```

### 全部参数

```text
--profile DIR    archiso profile 目录，默认 ./StardustArch
--out DIR        输出目录，默认 ./out
--cachedir NAME  持久化 Docker volume 名，默认 stardustarch-cache
                 必须是 volume 名，不能是宿主机路径；防止把 pacman 缓存放到 NTFS
--clean          删除 out/ 里旧的 stardustarch-*.iso 后重建
--rebuild-image  强制重建 stardustarch-builder 构建器镜像（默认复用已有镜像）
--shell          不构建，直接进入一次性 privileged 构建容器调试
-h, --help
```

示例：

```bash
# 清掉旧 ISO，重建
./build.sh --clean

# 使用独立缓存卷（例如不同分支）
./build.sh --cachedir stardustarch-cache-dev

# 进入构建容器排查 mkarchiso/calamares
./build.sh --shell
```

高级环境变量：

```bash
# 强制重新编译 Calamares（通常没必要）
STARDUST_FORCE_CALAMARES=1 ./build.sh

# 换构建器基础镜像
ARCH_IMAGE=archlinux:latest ./build.sh
```

### 构建产物

```text
out/stardustarch-YYYY.MM.DD-x86_64.iso
out/stardustarch-YYYY.MM.DD-x86_64.iso.sha256
out/stardustarch-build-info.txt
```

校验：

```bash
cd out
sha256sum -c stardustarch-*.iso.sha256
```

### 构建选项（`user.conf`）

`user.conf` 被容器内脚本 `source`，集中管理：

| 变量 | 默认 | 作用 |
|---|---|---|
| `INSTALL_DESKTOP` | `yes` | 是否整组安装 `packages.desktop` |
| `INSTALL_SPEED_TWEAKS` | `yes` | 是否加入 `packages.speed` |
| `ENABLE_ZRAM` | `yes` | 是否安装并启用 zram-generator 配置 |
| `INSTALL_PARU` | `no` | 是否额外构建/预装 `paru-bin` |
| `USE_REFLECTOR` / `MIRROR_COUNTRY` | `yes` / `CN` | 构建容器内用 reflector 选国内镜像 |
| `BUILD_JOBS` | `6` | Calamares 并行编译数；8 GB WSL 不要用 `-j$(nproc)` 硬冲 |
| `SQUASHFS_COMPRESSION` / `SQUASHFS_LEVEL` | `zstd` / `15` | 生成 profiledef 的 squashfs 压缩参数；改这里即可 |
| `EARLY_KMS` | `none` | `none/intel/amdgpu/nvidia/nvidia-open`，见下 |
| `EXTRA_PKGS` | `()` | 额外官方仓库包 |
| `ARCHLINUXCN_SERVER` / `CHINA_MIRRORS` | 见文件 | 安装器“Repositories”页使用的地址（文档性；实际值在 Calamares 模块配置） |

**Early KMS 说明**：

- `intel` → `MODULES=(i915)`；`amdgpu` → `MODULES=(amdgpu)`。这只影响 initramfs，不需要额外包。
- `nvidia` → 自动加 `nvidia nvidia-utils`，并写 `MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)` 与 `options nvidia_drm modeset=1 fbdev=1`。
- `nvidia-open` → 自动加 `nvidia-open nvidia-utils`，模块同 proprietary。
- **通用 ISO 默认必须为 `none`**：一旦把 NVIDIA 模块写进 initramfs，只为已知硬件构建还行；通用镜像应在安装后按目标显卡再启用。NVIDIA 驱动与具体 GPU 代数相关，选择错误可能无法进桌面。
- Intel 新核显若需要 `xe` 而非 `i915`，请把 `intel` 分支改成 `MODULES=(xe)`，并在真机验证。

---

## 三条硬约束的实现位置

### 约束 1：桌面只装 plasma-meta

| 要求 | 实现 |
|---|---|
| `packages.kde` 只列桌面 meta | `packages.kde` 中唯一桌面 meta 是 `plasma-meta`；没有 `kde-applications-meta` |
| 最小配套 | `sddm`、`sddm-kcm`、`xorg-server`（SDDM X11 greeter）、`xorg-xwayland`、`qt6-wayland`、`pipewire*`、`wireplumber`、`networkmanager`、`wpa_supplicant`/`iw`、Noto 三件套、`fcitx5`/`fcitx5-rime`/`fcitx5-configtool`/`fcitx5-qt`/`fcitx5-gtk` |
| 日用软件不混入 | 浏览器/终端/文件管理器等全在 `packages.desktop`，可整体关闭 |
| Live 图形目标、SDDM、NM | `customize_airootfs.sh`：`systemctl set-default graphical.target`、`systemctl enable sddm.service NetworkManager.service` |
| Live 自动登录 | `airootfs/etc/sddm.conf.d/autologin.conf`：`[Autologin] User=stardust Session=plasma`、`[Theme] Current=breeze` |
| Live 用户 | `customize_airootfs.sh` 创建 `stardust`，`wheel` 及其他存在的硬件组，空密码 |
| 装到真机后删除 | `post-install-syu.sh` 和 `target-cleanup.sh` 都 `rm` 自动登录、Live sudo 规则、`userdel -r stardust`，并锁定空密码账户 |

> `archinstall` 后备流程不会解包本 Live rootfs，因此不会把 `stardust`/autologin 带入 archinstall 新建的系统；不要用“rsync 整个 Live 根”之类方式替代 Calamares。

### 约束 2：GUI 安装器 Calamares

| 要求 | 实现 |
|---|---|
| `packages.x86_64` 引入 calamares | 是；同时引入本地 `stardustarch-calamares-config` |
| Arch 官方仓库没有 calamares | 提供 `pkg/calamares/PKGBUILD`（AUR 3.4.2 改），构建进 `[customrepo]`；`pacman.conf` 中 `[customrepo]` 位于 `[core]` 之前 |
| 完整配置 | `settings.conf`、`modules/`、`branding/stardustarch/`（branding.desc、stylesheet.qss、壁纸、Logo、finished QML） |
| 模块 | partition、mount、unpackfs、fstab、bootloader、displaymanager、locale、keyboard、users、services、initcpiocfg/initcpio、finished 等 |
| 品牌 | 全部为原创星尘/轨道图形，不复用 Arch 官方 Logo；文档明示 derived |
| displaymanager 用 SDDM | `displaymanager.conf`：`displaymanagers: [sddm]`，`defaultDesktopEnvironment` 指向 Plasma Wayland |
| UEFI/BIOS | UEFI 用 systemd-boot；BIOS 由 Calamares bootloader 模块自动执行 GRUB 安装；ESP 挂 `/boot` 以适配 systemd-boot |
| 桌面快捷方式 + 自动启动 | `/usr/share/applications/stardustarch-calamares.desktop`、`/etc/xdg/autostart/stardustarch-calamares.desktop`、Live 用户桌面快捷方式 |
| 配置打包 | `stardustarch-calamares-config`，由 `[customrepo]` 安装；构建时从 airootfs 生成包并从 overlay 移除同路径，避免冲突 |

**为什么必须自建 Calamares**：截至本交付检查时，Arch 官方 `core`/`extra` 同步库中没有名为 `calamares` 的包（AUR 才有，当前 3.4.2）。官方仓库若未来收录，可把 `pkg/calamares` 删除，改用官方包；但 `stardustarch-calamares-config` 仍需自建。

**Calamares 构建差异**：

- `-DINSTALL_CONFIG=OFF`，避免与配置包争 `/etc/calamares`；
- **保留 `packagechooser`**（安装器“Repositories”页依赖它）；
- 跳过 dracut、dummy、initramfs、packagechooserq、openrc 等无关模块；
- 固定源码 tarball 与 sha256，不随 AUR HEAD 漂移。

### 约束 3：chroot 内执行一次完整升级

- 脚本全文：`StardustArch/airootfs/usr/share/stardustarch/post-install-syu.sh`
- 调用位置：`settings.conf` 的 `shellprocess@post-syu`，位于 `unpackfs`、`mount`、`networkcfg` 之后，`initcpiocfg`、`initcpio`、`bootloader`、`finished` 之前
- 配置片段：

```yaml
# modules/shellprocess-post-syu.conf
dontChroot: true
timeout: 3600
verbose: true
script:
    - command: "-/usr/bin/bash /usr/share/stardustarch/post-install-syu.sh ${ROOT}"
      timeout: 3600
      verbose: true
```

- 为什么是 `${ROOT}` 而不是写死 `/target`：Calamares 的 Mount 模块使用 `tempfile.mkdtemp(prefix="calamares-root-")` 作为 target，真实路径通常是 `/tmp/calamares-root-*`，并不保证是 `/target`。`${ROOT}` 是 Calamares shellprocess 官方展开变量，等价于 `/target` 的语义；脚本也接受手动执行时的 `/target` 默认值。
- 脚本内容顺序：
  1. 删除 Live autologin、Live sudo 规则、Live 用户、`archiso.conf`、空密码账户；
  2. 移除任何残留的空密码账户（锁定）；
  3. `pacman-key --init`；
  4. `pacman-key --populate archlinux`；
  5. 若安装时选了 archlinuxcn：先装 keyring、`pacman-key --populate archlinuxcn`，再把 `SigLevel` 从临时 `Optional TrustAll` 收紧为 `Required DatabaseOptional`；失败则禁用该仓库并继续；
  6. `pacman -Syu --noconfirm`；
  7. 重写 StardustArch 的 `/etc/os-release`（防止 `filesystem` 包升级把品牌换回上游）；
  8. 写 `/etc/stardustarch/postinstall.status`（success/failed），失败时追加 `/etc/motd` 警告；
  9. 无论如何 `exit 0`，且 shellprocess 命令前导 `-` 进一步保证不阻断安装。

> 该 `shellprocess` 放在 `users` 模块**之前**：先删除 Live `stardust`（UID 1000），Calamares 再创建真实用户，使真机第一个用户拿到 UID 1000，而不是留下 UID 空档。

- 日志固定为目标的 `/var/log/stardustarch-postinstall.log`。
- **失败处理**：不阻断安装；finished 页显示常驻提示“若失败，首次进系统后 `sudo pacman -Syu`”，并把细节指向该日志。这是故意的：网络在 Calamares 阶段可能仍然不可用。

---

## 安装时选择 archlinuxcn / 国内镜像

Calamares 的 “Repositories” 页（`packagechooser` + 自定义 Python job `stardustarch_options`）提供多选：

- **China mirrors**：把目标 `/etc/pacman.d/mirrorlist` 替换为清华、中科大、阿里、北外、官方 geo 镜像的 HTTPS 列表；原文件备份为 `mirrorlist.stardustarch-original`。
- **Arch Linux CN repository**：写 `/etc/pacman.d/stardustarch-archlinuxcn.conf`，并在目标 `/etc/pacman.conf` 末尾加入 `Include`。为了避免第三方仓库首次信任问题，安装阶段会：
  1. 临时使用 `SigLevel = Optional TrustAll`；
  2. 安装 `archlinuxcn-keyring`；
  3. `pacman-key --populate archlinuxcn`；
  4. 成功后把 SigLevel 改为 `Required DatabaseOptional`；失败则注释掉 Include，安装继续。

不勾选任何项也完全合法。选择结果写入目标 `/etc/stardustarch/install-options.conf`，供审计。

> 第三方仓库的信任边界由用户决定；本项目不默认启用 archlinuxcn。

---

## “尽可能快”逐条配置、收益、代价、回滚

| 配置/位置 | 收益 | 代价 | 安全/休眠 | 回滚 |
|---|---|---|---|---|
| squashfs zstd 15，`profiledef.sh` | Live 启动解压快，构建也比 xz 快 | ISO 比 xz 大约 10–25% | 不影响；不涉及休眠 | 改回 `-comp xz ...` 后重建 |
| initramfs zstd + 精简 archiso hooks，`airootfs/etc/mkinitcpio.conf.d/archiso.conf` | 更小 initramfs、更少加载 | 不再带 PXE 启动 | 无 | 恢复上游 hooks/压缩，`mkinitcpio -P` |
| Calamares 包与 pacman cache 持久化 Docker volume | 第二次构建快很多 | 占磁盘 | 无 | `docker volume rm stardustarch-cache`（会清缓存） |
| `ParallelDownloads = 20`，`pacman.conf` | 构建下载并行 | 带宽/镜像压力 | 无 | 改回 5 |
| 构建容器 reflector `--country CN` | 国内构建下载更快 | 境外构建可能变慢；镜像状态变化 | 无 | `USE_REFLECTOR=no` 或改 `MIRROR_COUNTRY` |
| zram-generator，`airootfs/etc/systemd/zram-generator.conf` | 替代磁盘 swap，减少 I/O；内存压缩 | 占 CPU/内存；大内存机器收益递减 | **不支持休眠**；回退用 swapfile | 删配置、`swapoff /dev/zram0`、停止 zram unit、`daemon-reload` |
| `vm.swappiness=180`、`page-cluster=0` | 更积极用 zram | 更早换出匿名页，CPU 上升 | 不改变安全；休眠仍需磁盘 swap | 删 `/etc/sysctl.d/99-stardustarch-zram.conf` 后 `sysctl --system` |
| ext4/xfs `noatime,lazytime`，Calamares mount 模块 | 减少 atime 写入 | 应用看不到精确 atime | 无 | 编辑 `/etc/fstab` 去掉选项，`mount -o remount /` |
| btrfs `compress=zstd:1` | 省空间、部分读放大 | 压缩 CPU | 无 | 去掉 `compress=` 并 remount |
| 不建磁盘 swap（Calamares 默认 none） | 少一个分区/写入 | 休眠不可用；极端内存压力更依赖 zram | 休眠需手动 swapfile | 安装时选 swapfile 或手动 `mkswap/swapon` |
| KWin `blurEnabled=false`、`contrastEnabled=false`，skel `kwinrc` | 降低 GPU 合成负载，低端核显更跟手 | 失去模糊视觉 | 无 | 改回 `true`，重启 Plasma |
| Baloo `Indexing-Enabled=false`，skel `baloofilerc` | 减少后台 I/O/CPU | 文件全文搜索变弱 | 无 | 改回 `true`，重启 Plasma |
| `AnimationDurationFactor=0.5`，skel `kdeglobals` | 动画更短、主观更快 | 动画不完整 | 无 | 改回 1.0 |
| 只装 `plasma-meta`，不叠加 `kde-applications-meta` | 少装大量 KDE 应用与服务 | 需要时自行安装 | 无 | 自行 `pacman -S` 所需应用 |
| 禁用 `NetworkManager-wait-online` | 不等网络就进图形 | 依赖网络早启动的服务需自行调整 | 无 | `systemctl enable NetworkManager-wait-online.service` |
| `systemd-timesyncd`、`fstrim.timer`、`apparmor`、`bluetooth`、`power-profiles-daemon` | 时间同步/SSD 维护/安全/蓝牙/功耗 | 少量后台活动 | AppArmor 提升安全 | `systemctl disable` 对应 unit |
| `lsm=landlock,lockdown,yama,integrity,apparmor`（Live + target） | 明确启用 AppArmor 等 LSM | 与 SELinux/Smack 不并存；本项目不装它们 | 提升安全；无已知启动代价 | 从 `/etc/kernel/cmdline` 或 GRUB cmdline 移除，重建启动项 |
| 不用 `nowatchdog`、不用 `mitigations=off` | 保留安全缓解和 watchdog | 少一点“跑分” | **安全优先** | 无需回滚（没有添加） |
| 内核/模块/固件 zstd | Arch 软件包已是 zstd；initramfs 又显式 zstd | 几乎无 | 无 | 不需要 |
| early KMS（可选，默认关） | 减少开机闪屏/黑屏时间 | 需匹配 GPU；NVIDIA 驱动体积大 | 选错可能无显示 | 删除 `20-stardustarch-early-kms.conf` 和 `modprobe.d` 文件，`mkinitcpio -P` |

### NVIDIA / AMD / Intel 的 early KMS 建议

- **AMD**：内核自带 `amdgpu`，一般不需要 early KMS；需要时可 `MODULES=(amdgpu)`。不要同时启用 `radeon`。
- **Intel**：较老核显 `i915`，新平台可能 `xe`；不要盲目两个都放。用 `lspci -k` 确认当前内核加载的模块。
- **NVIDIA 专有**：`nvidia nvidia_modeset nvidia_uvm nvidia_drm` + `nvidia_drm.modeset=1`（新一代可加 `fbdev=1`）。只对已知 GPU 构建 ISO；通用 ISO 安装后再加。
- **NVIDIA 开源**：`nvidia-open` + 相同模块与参数，面向 Turing 及更新；老卡用 proprietary。
- 任何 early KMS 修改后：`sudo mkinitcpio -P`，然后重启验证；失败时用 Live ISO 删除 drop-in 并重建。

---

## 构建与测试边界：WSL2 + Docker 能做什么

### 可以在 WSL2 + Docker 完成

- 构建 ISO、生成 sha256、`stardustarch-build-info.txt`；
- 静态检查：`bash -n`、Python 编译、YAML 解析、branding/合规检查；
- 在容器内 `pacstrap`/`mkarchiso`（真正编译）；
- 在 WSL2 内用 QEMU（无 KVM 时 TCG）做**功能性**冒烟测试，速度不代表真机；
- 校验 ISO 内的 `/etc/os-release`、脚本、包列表（挂载或 `unsquashfs` 后）。

### 必须真机 / VMware / 物理 U 盘

- 真实 GPU 加速、Wayland 会话、KWin 合成、视频硬解；
- 真实声卡/PipeWire、蓝牙、Wi-Fi、休眠/唤醒；
- Secure Boot、真实 UEFI 固件、双系统 GRUB/Windows 启动项；
- 笔记本电池、电源管理、散热与风扇策略；
- USB 启动、Rufus/Ventoy 兼容性；
- 最终 `systemd-analyze` 对比和“体感”验收。

### QEMU（WSL2 内）

辅助脚本：

```bash
# 依赖：Arch WSL 内安装 qemu-system-x86 edk2-ovmf
# 用法：./scripts/qemu-run.sh out/stardustarch-*.iso [uefi|bios]
./scripts/qemu-run.sh out/stardustarch-2026.11.22-x86_64.iso uefi
```

- WSL2 通常没有 `/dev/kvm`，脚本会自动退回 TCG；**TCG 下 Plasma 启动很慢，不能用来评价性能**。
- 若主机开启嵌套虚拟化且 `/dev/kvm` 存在，可用 KVM，性能接近虚拟机。
- Docker Desktop 内的容器不适合跑 QEMU；请在 WSL2 发行版里跑 QEMU。
- 更推荐 **VMware Workstation/Player**（3D 加速、UEFI、USB）或 **Rufus 写 U 盘** 实机验证。

---

## 自检/验收清单

### A. 构建与介质

```bash
cd out
sha256sum -c stardustarch-*.iso.sha256
ls -lh
```

- [ ] ISO 与 sha256 同名同目录；
- [ ] `stardustarch-build-info.txt` 中 custom 包包含 `calamares-3.4.2-*` 和 `stardustarch-calamares-config-1.0.0-*`；
- [ ] `xorriso -indev <iso> -report_el_torito` 能看到 BIOS 在前、UEFI 在后（若工具可用）；
- [ ] 用 Rufus/Ventoy 或 VMware 启动，能进 Live SDDM 并自动登录 `stardust`。

### B. Live 环境

- [ ] 5 秒内出现 SDDM → 自动登录 Plasma Wayland；
- [ ] 桌面有 “Install StardustArch” 图标；Calamares 自动启动（若不希望自动启动，注释 `/etc/xdg/autostart` 文件后重建）；
- [ ] 终端 `sudo -n true` 成功（Live 免密）；
- [ ] NetworkManager 有网络；
- [ ] `fcitx5-diagnose` 无致命错误；Ctrl+Space 可切 Rime；
- [ ] `wpctl status` 能看到输出设备；
- [ ] `archinstall` 可执行（后备）。

### C. 用 Calamares 安装

- [ ] 分区页：UEFI 下 ESP 挂载点必须是 `/boot`（默认已配）；BIOS 下可用 msdos/GPT + GRUB；
- [ ] 用户页：没有 `stardust` 可选（被 forbidden）；必须设置 ≥8 位密码；root 密码单独设置；
- [ ] “Repositories” 页可选择/不选；
- [ ] 安装过程能看到 “Full system upgrade” 步骤；
- [ ] finished 页出现 StardustArch 品牌和升级失败提示。

### D. 安装后硬性检查

挂载目标或首次进入系统后：

```bash
# 1. 品牌与派生声明
grep -E '^(NAME|PRETTY_NAME|ID|ID_LIKE)=' /etc/os-release
# 期望：NAME=StardustArch；ID=stardustarch；ID_LIKE=arch；PRETTY_NAME 含 derived from Arch Linux

# 2. 升级日志与状态
sudo cat /var/log/stardustarch-postinstall.log
cat /etc/stardustarch/postinstall.status
# 期望：success（若 failed，见日志和 finished 页提示）

# 3. Live 身份没有进系统
id stardust            # 应失败
test ! -e /etc/sddm.conf.d/autologin.conf && echo "no autologin"
test ! -e /etc/sudoers.d/10-stardust-live && echo "no live sudo"

# 4. 目标与显示管理器
systemctl get-default  # graphical.target
systemctl status sddm NetworkManager --no-pager
systemctl status systemd-timesyncd --no-pager

# 5. 桌面/音频/网络/时间/中文
echo "$XDG_SESSION_TYPE"          # wayland
wpctl status | head
nmcli device status
timedatectl
fcitx5-diagnose

# 6. zram / 挂载 / LSM
zramctl
swapon --show
findmnt -no OPTIONS /
cat /sys/kernel/security/lsm
```

- [ ] `id stardust` 失败；
- [ ] `/etc/sddm.conf.d/autologin.conf` 不存在；
- [ ] `/etc/sudoers.d/10-stardust-live` 不存在；
- [ ] `postinstall.status` 为 success；若 failed，手动 `sudo pacman -Syu` 成功；
- [ ] 重启进入 Plasma，网络/声音/显卡加速/休眠（若有 swapfile）/AUR（若装 paru）/时间同步/中文输入正常；
- [ ] `sudo systemctl hibernate` 只有在用户自建 swapfile 并配置 resume 后才应工作；默认不应假装支持。

### E. `systemd-analyze` 量化对比

必须使用同一台机器/同一 VM、相同固件、相同磁盘、冷启动，至少 3 次取中位数：

```bash
systemd-analyze
systemd-analyze critical-chain
systemd-analyze blame | head -30
```

对比对象：官方 Arch ISO 安装后的同版本 Plasma（或最小系统），记录：

| 指标 | 官方 Arch | StardustArch | 差值 |
|---|---:|---:|---:|
| firmware + loader | | | |
| kernel | | | |
| userspace | | | |
| graphical.target | | | |
| 首次登录到桌面可用 | | | |

> 本交付**没有**实测数字，不虚构提升百分比。zstd squashfs 的启动收益通常最明显；`systemd-analyze` 的 userspace 时间主要受服务集和磁盘影响。

---

## 回滚手册

> 以下命令在**已安装的 StardustArch** 中执行。改内核启动参数前先备份 ESP/`/boot` 和 `/etc/default/grub`。

### 1. zram → 磁盘 swap

```bash
sudo systemctl disable --now systemd-zram-setup@zram0.service 2>/dev/null || true
sudo swapoff /dev/zram0 2>/dev/null || true
sudo rm -f /etc/systemd/zram-generator.conf /etc/sysctl.d/99-stardustarch-zram.conf
sudo systemctl daemon-reload
sudo sysctl --system
# 然后按需创建 swapfile/分区并写入 /etc/fstab
```

### 2. `noatime,lazytime` / btrfs 压缩

```bash
sudo cp /etc/fstab /etc/fstab.bak
sudo sed -i 's/,noatime,lazytime//; s/,lazytime//; s/,compress=zstd:1//' /etc/fstab
sudo mount -o remount /
```

### 3. KWin 模糊/Baloo/动画

```bash
# 恢复 KWin 模糊和对比度
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key contrastEnabled true
# 恢复 Baloo
kwriteconfig6 --file baloofilerc --group "Basic Settings" --key "Indexing-Enabled" true
# 恢复动画
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 1.0
# 重新登录 Plasma
```

### 4. 服务

```bash
sudo systemctl enable NetworkManager-wait-online.service
sudo systemctl disable bluetooth.service power-profiles-daemon.service fstrim.timer
# 按需
```

### 5. initramfs / LSM

```bash
# 删除自定义 early KMS 或 speed drop-in 后
sudo rm -f /etc/mkinitcpio.conf.d/20-stardustarch-early-kms.conf
sudo rm -f /etc/modprobe.d/stardustarch-nvidia.conf
sudo mkinitcpio -P

# systemd-boot：编辑 /etc/kernel/cmdline，去掉 lsm=... 后
sudo bootctl update
# 或重新生成对应启动项
# GRUB：编辑 /etc/default/grub 的 GRUB_CMDLINE_LINUX_DEFAULT，去掉 lsm=... 后
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### 6. 安装器/配置包残留

正常情况下安装后已自动删除：

```bash
pacman -Q calamares stardustarch-calamares-config 2>/dev/null
test ! -e /etc/calamares && echo "clean"
```

如果因异常中断需要手工清理，**先确认目标可正常启动，再**：

```bash
sudo pacman -R --noconfirm stardustarch-calamares-config calamares archinstall mkinitcpio-archiso archiso syslinux 2>/dev/null || true
sudo rm -rf /etc/calamares /usr/share/stardustarch /usr/lib/calamares/modules/stardustarch_options
sudo rm -f /etc/sddm.conf.d/autologin.conf /etc/sudoers.d/10-stardust-live
sudo userdel -r stardust 2>/dev/null || true
```

### 7. 恢复 Live 自动登录（仅用于调试 Live，不要用于真机）

```bash
sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null <<'EOF'
[Autologin]
User=stardust
Session=plasma
Relogin=false
[Theme]
Current=breeze
EOF
```

---

## 已知风险与注意事项

1. **Calamares 以 root 运行在 Wayland 会话**：Live 启动器使用 `sudo -E calamares`。若在特定 GPU/合成器下无法连到 Wayland，可临时改用 X11 会话调试：在 SDDM 登录界面选择 `Plasma (X11)`（需另装 `plasma-x11-session`），或设置 `QT_QPA_PLATFORM=xcb`。这是 Live 安装器体验风险，不影响已安装系统。
2. **SDDM greeter 是 X11**：为保证无 Wayland greeter 依赖时仍能显示登录界面，安装了 `xorg-server`；Plasma 会话仍是 Wayland。可通过 `plasma-x11-session` 增加 X11 会话，但默认不装。
3. **Calamares 版本固定为 3.4.2**：配置按 3.4.x 编写；升级 Calamares 后必须重新跑 `--shell` 里的 `calamares -d` 并用 Debug 页核对模块 key。AUR 源或 sha256 变化时更新 `pkg/calamares/PKGBUILD`。
4. **自定义仓库未签名**：`[customrepo]` 使用 `SigLevel = Optional TrustAll`，仅限构建容器；它不会进入目标系统。不要把该仓库公开为二进制源。
5. **AUR 包信任**：`pkg/calamares` 基于 AUR 3.4.2 的 PKGBUILD；`paru-bin` 基于 AUR 2.2.1 的预编译 release。若你不信任构建时下载的二进制，设 `INSTALL_PARU=no`（默认），并自行从源码构建 Calamares。
6. **示例 URL**：`os-release`、branding、PKGBUILD 中的 `example.org` 是占位符，发布前替换为真实项目主页；不要使用 Arch 官方域名或暗示官方背书。
7. **未实测**：当前环境没有可用的 Docker，不能证明“已构建成功”。交付的是完整源码与构建脚本；必须在本机执行一次真实构建和真机/VM 验收。
8. **休眠**：默认 zram + 无磁盘 swap，**休眠不可用是预期行为**。需要休眠时自行创建 swapfile，并配置 `resume=`/`resume_offset=`；不要以为 zram 能休眠。
9. **安全启动**：ISO 的 systemd-boot/GRUB 未做 Secure Boot 签名。真机如开启 Secure Boot，需自行签名或关闭 Secure Boot 测试。
10. **空密码 Live 用户**：这是 Live ISO 的便利设计，不是安装后配置。若你修改了 Calamares 序列或删除清理脚本，必须自行保证目标没有 `stardust` 空密码账户。

---

## 验证状态（本次交付）

已在 WSL2 的 Arch 环境执行：

- `bash -n`：全部 shell 脚本通过；
- `python3 -m py_compile`：`stardustarch_options/main.py` 通过；
- YAML 解析：Calamares 的 `settings.conf`、`modules/*.conf`、`branding.desc`、`module.desc` 全部通过（PyYAML 6.0.4，临时解包，不污染系统）；
- 关键合规检查：`os-release` 品牌/派生声明、`plasma-meta` 唯一桌面 meta、`nowatchdog`/`mitigations=off` 未启用、autologin 双清理、三条 `pacman-key`/`pacman -Syu` 命令存在；
- 包名可用性：对照 Arch `core`/`extra` 同步库检查了主要软件包；`calamares` 确认不在官方仓库，必须走 `[customrepo]`；
- `stardustarch-calamares-config`：已在本机用 `makepkg --nodeps` 实际构建成功（209 KiB 包，包含 `/etc/calamares`、品牌 PNG、Python 模块和两个安装后脚本）；
- Calamares 3.4.2 与 paru-bin 2.2.1 的下载源 sha256 已实际下载核对，与 PKGBUILD 一致。

未执行：

- `docker build` / `mkarchiso` / ISO 启动：当前会话未检测到 Docker CLI/Daemon（Arch WSL 中 `command -v docker` 为空），无法生成 ISO；
- QEMU/VMware、真机声卡/显卡/休眠/蓝牙/中文输入：需要你的硬件环境。

建议下一步：在启用了 Docker Desktop WSL Integration 的 Arch WSL 中执行：

```bash
cd /path/to/StardustArch
./build.sh --clean
```

然后把 `out/` 里的 ISO 交给 VMware 或 Rufus 做真实启动验收。

---

## 许可与品牌

- 本项目自有配置、脚本、QSS、QML、Logo、banner：MIT。
- **`bg.png` 及其转换生成的 `wallpaper.jpg` / `calamares-wallpaper.jpg` 由项目使用者提供，不在 MIT 范围内**；发布或再分发前请自行确认图片版权/授权。原图 7378×4611、约 67 MB；构建只打包压暗后的 2560×1600 JPEG（约 0.5 MB，finished 页/放映用）和 1000×680 的 Calamares 窗口裁剪（约 0.12 MB），避免 Calamares 加载超大图、也避免 `background-repeat` 平铺错位。
- Calamares 本体：GPL-3.0-or-later（由 `pkg/calamares` 构建）。
- Arch Linux 名称与标识属于 Arch Linux 项目；StardustArch **不**使用其官方 Logo，不声称官方身份或背书。
- `os-release` 使用 `ID=stardustarch`、`ID_LIKE=arch`，并在 `PRETTY_NAME` 中写明 derived from Arch Linux。
