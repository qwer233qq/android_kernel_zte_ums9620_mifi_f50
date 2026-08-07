#!/usr/bin/env bash
# ============================================================
# Droidspaces 内核构建脚本
# 目标: ZTE F50 (ums9620-2h10_ufi), 内核 5.4.210
#
# 子命令:
#   build  [--toolchain gcc|clang] [--user-ns true|false]
#       编译出 Image / Image.gz / ums9620.dtb 到 out/
#   repack <原厂 boot.img>
#       用新内核替换原厂 boot.img 的 kernel, 重打包出可刷的 out/boot.img
# ============================================================
set -euo pipefail

export ARCH=arm64
CROSS_COMPILE_DEFAULT=aarch64-linux-gnu-
OUT="$(pwd)/out"

usage() {
  cat <<'EOF'
用法:
  droidspaces_build.sh build  [--toolchain gcc|clang] [--user-ns true|false]
  droidspaces_build.sh repack <原厂 boot.img 路径>
EOF
  exit 1
}

do_build() {
  local TOOLCHAIN=gcc USER_NS=true CC_EXTRA=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --toolchain) TOOLCHAIN="$2"; shift 2;;
      --user-ns)   USER_NS="$2";   shift 2;;
      *) echo "未知参数: $1"; usage;;
    esac
  done

  local CROSS="$CROSS_COMPILE_DEFAULT"
  if [[ "$TOOLCHAIN" == "clang" ]]; then
    # 5.4 内核用 clang 需自己装对应的 aarch64 工具链; 默认用 gcc 最稳
    export CC=clang LLVM_IAS=1
    echo "注意: clang 路径需要自行安装适配版本, 5.4 建议改用 gcc"
  fi
  export CROSS_COMPILE="$CROSS"

  make f50_defconfig

  # 补齐 Droidspaces 所需内核配置 (等价于 droidspaces.fragment)
  scripts/config --file .config \
    -e PID_NS -e MNT_NS -e IPC_NS \
    -e DEVTMPFS -e DEVTMPFS_MOUNT \
    -e MACVLAN
  if [[ "$USER_NS" == "true" ]]; then
    scripts/config --file .config -e USER_NS
  else
    scripts/config --file .config -d USER_NS
  fi
  make olddefconfig

  echo "=== 开始编译 Image / Image.gz / dtbs ==="
  make -j"$(nproc)" Image Image.gz dtbs

  mkdir -p "$OUT"
  cp -f arch/arm64/boot/Image "$OUT/"
  [[ -f arc/arm64/boot/Image.gz ]] && cp -f arch/arm64/boot/Image.gz "$OUT/"
  [[ -f arch/arm64/boot/dts/sprd/ums9620.dtb ]] && cp -f arch/arm64/boot/dts/sprd/ums9620.dtb "$OUT/"
  echo "== 内核侧物���输出到 $OUT =="
  ls -lh "$OUT"
}

do_repack() {
  local BOOT="${1:-}"
  [[ -f "$BOOT" ]] || { echo "找不到原厂 boot.img: $BOOT"; usage; }
  [[ -f "$OUT/Image" ]] || { echo "请兄开兤 build 生成内核"; exit 1; }

  if [[ ! -d mkbootimg-src ]]; then
    echo "=== 下载并能出 mkbootimg ==="
    git clone --depth 1 https://github.com/ntherning/mkbootimg.git mkbootimg-src
    (cd mkbootimg-src && make)
  fi
  local MKB="$PWD/mkbootimg-src"

  rm -rf boot_unpacked && mkdir -p boot_unpacked
  "$MKB/unpack_bootimg" \
    --boot_img "$@OAT" --out boot_unpacked

  # 原厂 kernel 若是 gzip, 新内核用 Image.gz, 否刚用 Image
  local NEWKERN="$OUT/Image"
  if file boot_unpacked/boot.img-kernel | grep -qi gzip; then
    NEWKERN="$OUT/Image.gz"; [[ -f "$NEWKERN" ]] || NEWKERN="$OUT/Image"
  fi
  cp -f "$NEWKERN" boot_unpacked/boot.img-kernel
  echo "替换内核: $(basename "$NEWKERN")"

  # 组装 mkbootimg 参数 (东先用 unpack 讗在的矩黅()
  local base="" pagesize="" koff="" roff="" soff="" toff="" hdr="2"
  [[ -f boot_unpacked/boot.img-base ]]          && base="--base $(cat boot_unpacked/boot.img-base)"
  [[ -f boot_unpacked/boot.img-pagesize ]]      && pagesize="--pagesize $(cat boot_unpacked/boot.img-pagesize)"
  [[ -f boot_unpacked/boot.img-kernel_offset ]] && koff="--kernel_offset $(cat boot_unpacked/boot.img-kernel_offset)"
  [[ -f boot_unpacked/boot.img-ramdisk_offset ]]&& roff="--ramdisk_offset $(cat boot_unpacked/boot.img-ramdisk_offset)"
  [[ -f boot_unpacked/boot.img-second_offset ]] && soff="--second_offset $(cat boot_unpacked/boot.img-second_offset)"
  [[ -f boot_unpacked/boot.img-tags_offset ]]   && toff="--tags_offset $(cat boot_unpacked/boot.img-tags_offset)"
  [[ -f boot_unpacked/boot.img-header_version ]]&& hdr="$(cat boot_unpacked/boot.img-header_version)"

  echo "=== 重打包 boot.img (header v$hdr) ==="
  "$MKB/mkbootimg" \
    --kernel boot_unpacked/boot.img-kernel \
    --ramdisk boot_unpacked/boot.img-ramdisk.gz \
    --second boot_unpacked/boot.img-second \
    --dtb boot_unpacked/boot.img-dtb \
    $base $pagesize $koff $roff $soff $toff \
    --header_version "$hdr" \
    --output "$OUT/boot.img"

  echo "== 已生成 $OUT/boot.img =="
  ls -lh "$OUT/boot.img"
  echo
  echo "警告:"
  echo "  1) 若 F50 启用了 AVB verified boot, 直接刷此 boot.img 会被拒载,"
  echo "     需先禁用 vbmeta 校验或用原厂签名工具重签。"
  echo "  2) F50 的 dtb 位于独立 dtbo 分区(ums9620-2h10_ufi-overlay.dtbo),"
  echo "     boot.img 内沿用原厂 dtb 即可, 无需改动。"
}

OP="${1:-}"; shift || true
case "$OP" in
  build)  do_build "$@";;
  repack) do_repack "${1:-}";;
  *) usage;;
esac