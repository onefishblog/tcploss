#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------------
# TCP 丢包测试脚本（支持 IPv4 + IPv6）
# 兼容：CentOS / Debian / Ubuntu
# 依赖：bash timeout nc awk
# --------------------------------------------------------

# 映射命令到安装包名
declare -A PKG_MAP=(
  [nc]="netcat"
  [timeout]="coreutils"
  [awk]="gawk"
)

# 检查并自动安装缺失组件（需 root/SUDO）
missing=()
for cmd in "${!PKG_MAP[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("${PKG_MAP[$cmd]}")
  fi
done

if (( ${#missing[@]} )); then
  echo "检测到缺少组件：${missing[*]}"
  if [[ "$EUID" -ne 0 ]]; then
    echo "请使用 root 或 sudo 运行以安装依赖。" >&2
    exit 1
  fi
  if command -v apt-get &>/dev/null; then
    apt-get update
    apt-get install -y "${missing[@]}"
  elif command -v yum &>/dev/null; then
    yum install -y "${missing[@]}"
  else
    echo "未识别包管理器，请手动安装：${missing[*]}" >&2
    exit 1
  fi
  echo "依赖安装完成。"
fi

# 默认参数
DEFAULT_COUNT=500
DEFAULT_TIMEOUT=1
DEFAULT_REMOTE_IP="::1"
DEFAULT_REMOTE_PORT=80

# 交互输入
read -rp "请输入握手尝试次数 [默认 $DEFAULT_COUNT]: " input
COUNT="${input:-$DEFAULT_COUNT}"
read -rp "请输入每次握手超时时间（秒） [默认 $DEFAULT_TIMEOUT]: " input
TIMEOUT="${input:-$DEFAULT_TIMEOUT}"
read -rp "请输入目标 IP（支持 IPv4 或 IPv6） [默认 $DEFAULT_REMOTE_IP]: " input
REMOTE_IP="${input:-$DEFAULT_REMOTE_IP}"
read -rp "请输入目标端口 [默认 $DEFAULT_REMOTE_PORT]: " input
REMOTE_PORT="${input:-$DEFAULT_REMOTE_PORT}"

# 检测 nc 是否支持地址族标志
SUPPORT_V6=false
SUPPORT_V4=false
if nc -h 2>&1 | grep -q -- ' -6'; then SUPPORT_V6=true; fi
if nc -h 2>&1 | grep -q -- ' -4'; then SUPPORT_V4=true; fi

# 根据 IP 自动选择 IPv4/IPv6
if [[ "$REMOTE_IP" == *:* ]]; then
  # IPv6 地址
  if [[ "$SUPPORT_V6" == "true" ]]; then
    AF_FLAG="-6"
  else
    AF_FLAG=""
  fi
else
  # IPv4 地址
  if [[ "$SUPPORT_V4" == "true" ]]; then
    AF_FLAG="-4"
  else
    AF_FLAG=""
  fi
fi

# 开始测试
succ=0
fail=0

echo -e "\n开始测试 $REMOTE_IP:$REMOTE_PORT，总次数: $COUNT，超时: ${TIMEOUT}s"

for ((i=1; i<=COUNT; i++)); do
  if timeout "$TIMEOUT" nc $AF_FLAG -z "$REMOTE_IP" "$REMOTE_PORT" &>/dev/null; then
    ((succ++))
  else
    ((fail++))
  fi
  printf "\r已完成: %d/%d" "$i" "$COUNT"
done

# 结果输出
echo -e "\n\n测试完成"
echo "➜ 成功连接: $succ 次"
echo "➜ 失败连接: $fail 次"
pct=$(awk -v f=$fail -v s=$succ 'BEGIN{printf "%.2f", f/(f+s)*100}')
echo "➜ 粗略 TCP 丢包率 ≈ ${pct}%"
