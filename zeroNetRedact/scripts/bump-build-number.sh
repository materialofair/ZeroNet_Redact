#!/bin/sh
# 自动递增构建号（CFBundleVersion / CURRENT_PROJECT_VERSION）
# 仅 Release（Archive）构建时执行；Debug 构建不影响。
if [ "${CONFIGURATION}" != "Release" ]; then
  exit 0
fi

# SRCROOT = 工程目录（含 .xcodeproj 的目录）
SRC_DIR="${SRCROOT:-${PROJECT_FILE_PATH}}"
PBXPROJ="${SRC_DIR}/zeroNetRedact.xcodeproj/project.pbxproj"
if [ ! -f "${PBXPROJ}" ]; then
  echo "warning: bump-build-number: 未找到 ${PBXPROJ}（SRCROOT=${SRCROOT}）"
  exit 0
fi

current=$(/usr/bin/grep -m1 'CURRENT_PROJECT_VERSION = ' "${PBXPROJ}" | /usr/bin/sed 's/.*= *//; s/;//')
case "${current}" in
  ''|*[!0-9]*) echo "warning: bump-build-number: 无效构建号 '${current}'"; exit 0 ;;
esac

next=$((current + 1))
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION = ${current};/CURRENT_PROJECT_VERSION = ${next};/g" "${PBXPROJ}"

# 本次构建产物立即生效（脚本阶段早于代码签名）
PLIST="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
if [ -f "${PLIST}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${next}" "${PLIST}" 2>/dev/null || true
fi
echo "Build number auto-incremented: ${current} -> ${next}"
