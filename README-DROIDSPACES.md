# 为 ZTE F50 (ums9620) 编译 Droidspaces 内核

用 GitHub Actions 把 `Enceka/android_kernel_zte_ums9620_mifi_f50`(Linux **5.4.210**,
展锐 ums9620) 编译成适用 **Droidspaces** 容器运行时的内核, 并产出可刷写的 `boot.img`。

## 文件说明

| 文件 | 作用 |
|------|------|
| `.github/workflows/build-droidspaces-kernel.yml` | GitHub Actions 工作流 |
| `droidspaces.fragment` | Droidspaces 所需内核配置补丁(Kconfig fragment) |
| `scripts/droidspaces_build.sh` | 本地/CI 共用的编译 + 重打包脚本 |

## 内核配置结论(已核对 f50_defconfig)

Droidspaces 需要**真命名空间隔离**, 已核对该 defconfig 的现状:

| 配置项 | 现状 | 说明 |
|--------|------|------|
| `CONFIG_NAMESPACES` `UTS_NS` `NET_NS` | 已开 ✓ | |
| `CONFIG_PID_NS` | **未开 ✗** | Droidspaces 每容器独立 PID tree, 必须开启 |
| `CONFIG_MNT_NS` `IPC_NS` | 未确认, 补丁开启 | 需补 |
| `CONFIG_DEVTMPFS` `DEVTMPFS_MOUNT` | 未开 | 容器内 /dev, 建议开启 |
| `CONFIG_OVERLAY_FS` | 已开 ✓ | volatile(易失)模式依赖 |
| `CONFIG_VETH` `BRIDGE` `TUN` `PACKET` | 已开 ✓ | NAT/网络隔离 |
| `CONFIG_IP_NF_NAT` | 已开 ✓ | |
| `CONFIG_MACVLAN` | 未开 | 补丁可选开启 |
| `CONFIG_USER_NS` | 未开 | 补丁默认开启(可关) |

## 使用步骤

### 方式 A: 直接用 GitHub Actions(推荐)

1. 把这个仓库(F50 内核) fork / 推送到你自己的 GitHub 仓库, 并包含本目录的文件。
2. 到 Actions 页选择 **Build Droidspaces Kernel** 工作流, 点 **Run workflow**。
3. 输入参数:
   - `toolchain`: 保持 `gcc`(5.4 内核用 GCC 交叉编译最稳)
   - `enable_user_ns`: 建议 `true`
   - `original_boot_url`: **可选**。填你从原厂固件提取的 `boot.img` 直链, 工作流会自动
     unpack 原厂 boot(拿 ramdisk/cmdline/offset 参数), 替换成新内核后重打包出可刷的 `boot.img`。
     留空则只产出 `Image / Image.gz / ums9620.dtb`。
4. 构建完下载 artifact `droidspaces-f50-kernel`, 里面有 `boot.img`(若填了原厂包)。

### 方式 B: 本地编译

```bash
# 依赖: gcc-aarch64-linux-gnu, device-tree-compiler, libfdt-dev
sudo apt install gcc-aarch64-linux-gnu device-tree-compiler libfdt-dev

./scripts/droidspaces_build.sh build --toolchain gcc --user-ns true
# 产物在 out/ (Image, Image.gz, ums9620.dtb)

# 若有原厂 boot.img, 重打包:
./scripts/droidspaces_build.sh repack path/to/original_boot.img
```

## 重要提醒

1. **AVB 签名**: 苕 F50 bootloader 启用了 verified boot(AVB), 未签名的自编 `boot.img`
   会被拒载导致无法启动。这种情况需先禁用 vbmeta 校验, 或用原厂签名工具重签 boot 镜像。
2. **dtb 在 dtbo 分区**: F50 采用 `ums9620.dtb`(base) + `ums9620-2h10_ufi-overlay.dtbo`
   的 overlay 结构, dtb 单独放 dtbo 分区。重打包时沿用原厂 dtb 即可, 一般无需改动。
3. **ramdisk**: boot.img 的 ramdisk 沿用原厂(含 Android 初始化/init.rc), 重打包时保持原厂
   ramdisk 不替换。Droidspaces 在用户态跑 daemon, 无需改 init。
4. **内核对容器支持**: 编译产物默认已启用 PID/MNT/IPC/UTS/NET namespace、overlayfs、veth、
   bridge、tun 等, 满足 Droidspaces 对宿主机内核的要求。