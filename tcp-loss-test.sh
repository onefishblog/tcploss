#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# TCP 握手丢包测试脚本
# 兼容：CentOS/Debian/Ubuntu
# 功能：缺少 timeout 或 awk 时自动安装（需 root 权限，安装时会提示 Y/n）
# 用法：chmod +x tcp-loss-test.sh
#      ./tcp-loss-test.sh [-c 次数] [-t 超时时间(秒)] <目标IP> <目标端口>
# -----------------------------------------------------------------------------

# 映射命令到包名
declare -A PKG_MAP=(
  ["timeout"]="coreutils"
  ["awk"]="gawk"
)

# 检查并安装缺失组件
missing_pkgs=()
for cmd in "${!PKG_MAP[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    missing_pkgs+=("${PKG_MAP[$cmd]}")
  fi
done

if [ ${#missing_pkgs[@]} -gt 0 ]; then
  echo "检测到缺少组件：${missing_pkgs[*]}"
  # 必须 root 权限才能安装
  if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行脚本，以安装缺少的组件。" >&2
    exit 1
  fi

  # 选择包管理器
  if   command -v apt-get &>/dev/null; then
    pkg_mgr="apt-get"
    update_cmd="apt-get update"
    install_cmd="apt-get install"
  elif command -v yum     &>/dev/null; then
    pkg_mgr="yum"
    update_cmd=""               # yum install 会自动 refresh
    install_cmd="yum install"
  else
    echo "未检测到 apt-get 或 yum，请手动安装：${missing_pkgs[*]}" >&2
    exit 1
  fi

  # 更新索引（如果需要）
  if [ -n "$update_cmd" ]; then
    echo "正在更新包索引……"
    $update_cmd
  fi

  # 安装缺失包（会提示 Y/n）
  echo "将安装：${missing_pkgs[*]}"
  $install_cmd "${missing_pkgs[@]}"
  echo "组件安装完成。"
fi

# 默认参数
COUNT=500
TIMEOUT=1

# 参数解析
usage() {
  cat <<EOF >&2
用法: $0 [-c 次数] [-t 超时时间(秒)] <目标IP> <目标端口>

  -c 次数        握手尝试次数，默认 $COUNT
  -t 超时时间    每次握手超时时间（秒），默认 $TIMEOUT
EOF
  exit 1
}

while getopts ":c:t:" opt; do
  case $opt in
    c) COUNT="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

[ $# -eq 2 ] || usage
REMOTE_IP="$1"
REMOTE_PORT="$2"

succ=0
fail=0

echo "开始在 $REMOTE_IP:$REMOTE_PORT 上进行 $COUNT 次 TCP 握手测试 (超时 ${TIMEOUT}s)…"
for ((i=1; i<=COUNT; i++)); do
  if timeout "${TIMEOUT}" bash -c "exec 3<>/dev/tcp/${REMOTE_IP}/${REMOTE_PORT}" &>/dev/null; then
    ((succ++))
    exec 3>&- 3<&- || true
  else
    ((fail++))
  fi
done

# 输出结果
echo
echo "测试完成，共尝试 ${COUNT} 次"
echo "➜ 成功握手（收到 RST 或完成三次握手）: ${succ} 次"
echo "➜ 握手失败（超时或网络不可达）         : ${fail} 次"
pct=$(awk -v f=$fail -v s=$succ 'BEGIN{printf "%.2f", f/(f+s)*100}')
echo "➜ 粗略 TCP 丢包率 ≈ ${pct}%"
