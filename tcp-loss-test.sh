#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# 交互式 TCP 丢包测试脚本
# 兼容：CentOS/Debian/Ubuntu（自动安装缺失依赖，需要 root 权限并会提示 Y/n）
# 功能：交互输入握手次数、超时时间、目标 IP、目标端口；也可直接回车使用默认值
# -----------------------------------------------------------------------------

# 映射命令到包名
declare -A PKG_MAP=(
  ["timeout"]="coreutils"
  ["awk"]="gawk"
)

# 检查并安装缺失组件
missing=()
for cmd in "${!PKG_MAP[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("${PKG_MAP[$cmd]}")
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "检测到缺少组件：${missing[*]}"
  if [ "$EUID" -ne 0 ]; then
    echo "请用 root 或 sudo 运行以安装依赖。" >&2
    exit 1
  fi

  if command -v apt-get &>/dev/null; then
    echo "更新 apt 索引…"
    apt-get update
    echo "安装 ${missing[*]}（输入 Y 确认）…"
    apt-get install "${missing[@]}"
  elif command -v yum &>/dev/null; then
    echo "安装 ${missing[*]}（输入 Y 确认）…"
    yum install "${missing[@]}"
  else
    echo "未识别包管理器，请手动安装：${missing[*]}" >&2
    exit 1
  fi
  echo "依赖安装完成。"
fi

# 默认值
DEFAULT_COUNT=500
DEFAULT_TIMEOUT=1
DEFAULT_REMOTE_IP="127.0.0.1"
DEFAULT_REMOTE_PORT=65535

# 交互式输入
read -rp "请输入握手尝试次数 [默认 ${DEFAULT_COUNT}]: " input
COUNT="${input:-$DEFAULT_COUNT}"

read -rp "请输入每次握手超时时间（秒） [默认 ${DEFAULT_TIMEOUT}]: " input
TIMEOUT="${input:-$DEFAULT_TIMEOUT}"

read -rp "请输入目标 IP [默认 ${DEFAULT_REMOTE_IP}]: " input
REMOTE_IP="${input:-$DEFAULT_REMOTE_IP}"

read -rp "请输入目标端口 [默认 ${DEFAULT_REMOTE_PORT}]: " input
REMOTE_PORT="${input:-$DEFAULT_REMOTE_PORT}"

echo
echo "配置如下："
echo "  次数：$COUNT"
echo "  超时：${TIMEOUT}s"
echo "  目标：$REMOTE_IP:$REMOTE_PORT"
echo

# 测试循环
succ=0
fail=0
echo "开始进行 TCP 握手测试…"
for ((i=1; i<=COUNT; i++)); do
  if timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/${REMOTE_IP}/${REMOTE_PORT}" &>/dev/null; then
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
echo "➜ 握手失败（超时或不可达）         : ${fail} 次"
pct=$(awk -v f=$fail -v s=$succ 'BEGIN{printf \"%.2f\", f/(f+s)*100}')
echo "➜ 粗略 TCP 丢包率 ≈ ${pct}%"
