#!/bin/sh
# 为下一次 Release 自动递增项目构建号；本次 app/扩展使用同一个已解析值。
# 不修改已生成或已签名的产物，避免主应用与分享扩展的版本号不一致。
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

next=$((current + 1))
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION = ${current};/CURRENT_PROJECT_VERSION = ${next};/g" "${PBXPROJ}"

echo "Current build: ${current}; next Release build: ${next}"
