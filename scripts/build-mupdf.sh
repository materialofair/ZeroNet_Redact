#!/bin/sh
# 构建 MuPDF 静态库（iOS 真机 + 模拟器，fat library）
#
# 产物：
#   third_party/mupdf-build/lib/libmupdf.a
#   third_party/mupdf-build/lib/libmupdf-third.a
#   third_party/mupdf-build/include/mupdf/...
#
# 用法：
#   scripts/build-mupdf.sh          # 产物已存在则跳过
#   scripts/build-mupdf.sh --force  # 强制重建

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO_ROOT/third_party/mupdf"
OUT="$REPO_ROOT/third_party/mupdf-build"
BUILD="$OUT/build"
EXPECTED_SHA="fe374accd98a43174a328fa7980d7675e06d5b0d" # MuPDF 1.28.2

if [ "$#" -gt 0 ] && [ "$1" = "--force" ]; then
    rm -rf "$OUT"
fi

if [ -f "$OUT/lib/iphoneos/libmupdf.a" ] && [ -f "$OUT/lib/iphoneos/libmupdf-third.a" ] \
   && [ -f "$OUT/lib/iphonesimulator/libmupdf.a" ] && [ -f "$OUT/lib/iphonesimulator/libmupdf-third.a" ] \
   && [ -d "$OUT/include/mupdf" ]; then
    echo "✅ MuPDF 产物已存在，跳过构建（使用 --force 强制重建）"
    exit 0
fi

if [ ! -f "$SRC/Makefile" ]; then
    echo "错误：third_party/mupdf 不存在或不完整，请先初始化子模块："
    echo "  git submodule update --init --recursive --depth 1"
    exit 1
fi

ACTUAL_SHA="$(git -C "$SRC" rev-parse HEAD)"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "错误：MuPDF 子模块版本不是预期值。"
    echo "  预期: $EXPECTED_SHA (1.28.2)"
    echo "  实际: $ACTUAL_SHA"
    exit 1
fi

mkdir -p "$BUILD"

HAVE_FLAGS="HAVE_GLUT=no HAVE_GLFW=no HAVE_X11=no"

build_arch() {
    name="$1"
    sdk="$2"
    target="$3"
    echo "==> 构建 $name"
    make -C "$SRC" -j"$(sysctl -n hw.ncpu)" \
        build=release \
        OUT="$BUILD/$name" \
        libs \
        $HAVE_FLAGS \
        CC="xcrun --sdk $sdk clang" \
        AR="xcrun --sdk $sdk ar" \
        RANLIB="xcrun --sdk $sdk ranlib" \
        XCFLAGS="-target $target -isysroot $(xcrun --sdk $sdk --show-sdk-path)"
}

build_arch ios-arm64 iphoneos "arm64-apple-ios17.0"
build_arch ios-sim-arm64 iphonesimulator "arm64-apple-ios17.0-simulator"
build_arch ios-sim-x86_64 iphonesimulator "x86_64-apple-ios17.0-simulator"

mkdir -p "$OUT/lib/iphoneos" "$OUT/lib/iphonesimulator"

# 真机 arm64
lipo -create "$BUILD/ios-arm64/libmupdf.a" -output "$OUT/lib/iphoneos/libmupdf.a"
lipo -create "$BUILD/ios-arm64/libmupdf-third.a" -output "$OUT/lib/iphoneos/libmupdf-third.a"

# 模拟器 arm64 + x86_64（设备库与模拟器库同为 arm64，不能合入同一 fat 文件）
lipo -create \
    "$BUILD/ios-sim-arm64/libmupdf.a" \
    "$BUILD/ios-sim-x86_64/libmupdf.a" \
    -output "$OUT/lib/iphonesimulator/libmupdf.a"

lipo -create \
    "$BUILD/ios-sim-arm64/libmupdf-third.a" \
    "$BUILD/ios-sim-x86_64/libmupdf-third.a" \
    -output "$OUT/lib/iphonesimulator/libmupdf-third.a"

rm -rf "$OUT/include"
cp -R "$SRC/include" "$OUT/include"
rm -rf "$BUILD"

echo "✅ MuPDF 静态库构建完成：$OUT"
