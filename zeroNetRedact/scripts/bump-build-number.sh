#!/bin/sh
# Release 构建期间只校验构建号；下一次构建号须在 Archive 开始前统一设置。
# 不在构建中修改工程或产物，避免工程重新载入及主应用/扩展版本不一致。
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

current=$(/usr/bin/grep -o 'CURRENT_PROJECT_VERSION = [0-9][0-9]*;' "${PBXPROJ}" | /usr/bin/sed 's/[^0-9]//g' | /usr/bin/sort -u)
case "${current}" in
  ''|*[!0-9]*) echo "error: bump-build-number: 各目标构建号必须是同一整数"; exit 1 ;;
esac

echo "Validated Release build: ${current}; project remains unchanged"
