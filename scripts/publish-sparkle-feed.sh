#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_DIR="${HOME}/Library/Developer/Xcode/DerivedData/PCL.Mac-dlhwgbjhdpbbyxefezmtvujyakce/SourcePackages/artifacts/sparkle/Sparkle"
GENERATE_APPCAST="${SPARKLE_DIR}/bin/generate_appcast"
GENERATE_KEYS="${SPARKLE_DIR}/bin/generate_keys"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print "用法：zsh scripts/publish-sparkle-feed.sh [archives-dir]"
  print ""
  print "环境变量："
  print "  DOWNLOAD_URL_PREFIX         更新包下载 URL 前缀"
  print "  RELEASE_NOTES_URL_PREFIX    发布说明 URL 前缀"
  print "  FULL_RELEASE_NOTES_URL      完整更新日志 URL"
  print "  PRODUCT_LINK                产品主页链接"
  print "  CHANNEL                     Sparkle 通道，例如 beta / beta-gray"
  print "  PHASED_ROLLOUT_INTERVAL     灰度放量间隔（秒）"
  print "  SPARKLE_ACCOUNT_NAME        Sparkle 签名账号名，默认使用 Bundle ID"
  exit 0
fi

ARCHIVES_DIR="${1:-${ROOT_DIR}/dist/sparkle}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"
RELEASE_NOTES_URL_PREFIX="${RELEASE_NOTES_URL_PREFIX:-}"
PRODUCT_LINK="${PRODUCT_LINK:-https://update.gzitvs.cn/projects/PCL.Mac.Refactor}"
FULL_RELEASE_NOTES_URL="${FULL_RELEASE_NOTES_URL:-}"
CHANNEL="${CHANNEL:-}"
PHASED_ROLLOUT_INTERVAL="${PHASED_ROLLOUT_INTERVAL:-}"
ACCOUNT_NAME="${SPARKLE_ACCOUNT_NAME:-cn.gzitvs.PCL-Mac}"

if [[ ! -x "${GENERATE_APPCAST}" ]]; then
  print "未找到 Sparkle 工具：${GENERATE_APPCAST}"
  print "请先运行一次 Xcode 构建，确保 Swift Package 已解析。"
  exit 1
fi

if [[ -z "${DOWNLOAD_URL_PREFIX}" ]]; then
  print "必须提供 DOWNLOAD_URL_PREFIX，例如："
  print "  DOWNLOAD_URL_PREFIX=https://update.gzitvs.cn/meta/PCL.Mac/stable/updates/ zsh scripts/publish-sparkle-feed.sh dist/sparkle"
  exit 1
fi

mkdir -p "${ARCHIVES_DIR}"

print "使用 Sparkle 账号：${ACCOUNT_NAME}"
"${GENERATE_KEYS}" --account "${ACCOUNT_NAME}" -p

command=("${GENERATE_APPCAST}" --account "${ACCOUNT_NAME}" --link "${PRODUCT_LINK}")

if [[ -n "${DOWNLOAD_URL_PREFIX}" ]]; then
  command+=(--download-url-prefix "${DOWNLOAD_URL_PREFIX}")
fi

if [[ -n "${RELEASE_NOTES_URL_PREFIX}" ]]; then
  command+=(--release-notes-url-prefix "${RELEASE_NOTES_URL_PREFIX}")
fi

if [[ -n "${FULL_RELEASE_NOTES_URL}" ]]; then
  command+=(--full-release-notes-url "${FULL_RELEASE_NOTES_URL}")
fi

if [[ -n "${CHANNEL}" ]]; then
  command+=(--channel "${CHANNEL}")
fi

if [[ -n "${PHASED_ROLLOUT_INTERVAL}" ]]; then
  command+=(--phased-rollout-interval "${PHASED_ROLLOUT_INTERVAL}")
fi

command+=("${ARCHIVES_DIR}")

print "开始生成 Sparkle appcast：${ARCHIVES_DIR}"
"${command[@]}"

print "已生成：${ARCHIVES_DIR}/appcast.xml"
print "如果目录里存在多个已签名的 zip/dmg，Sparkle 也会自动生成 delta 更新。"
