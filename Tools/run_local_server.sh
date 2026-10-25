#!/bin/bash
# Kinter 本地服务一键启动：AuthServer + serveo 公网隧道
# 用法：./Tools/run_local_server.sh
# 说明：
#   - 无需真实服务器，用这台 Mac 跑服务端，serveo 隧道暴露公网地址
#   - 免费隧道地址每次启动会变；浏览器访问有警告页（正常）
#   - 本机重启/关机后服务停止，重新运行本脚本即可
# 停止：Ctrl+C（前台）或 kill node + kill ssh
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8787
SERVER_DIR="/Users/mawenhao/MiniAppHost/AuthServer"
DATA_DIR="$SERVER_DIR/data"

echo "==> 1/3 启动 AuthServer (端口 $PORT)"
cd "$SERVER_DIR"
PORT=$PORT DATA_DIR=$DATA_DIR node server.js &
SERVER_PID=$!
trap 'kill $SERVER_PID $SSH_PID 2>/dev/null || true; exit' INT TERM

sleep 1
if ! curl -s "http://localhost:$PORT/healthz" | grep -q ok; then
  echo "服务端启动失败"; kill $SERVER_PID; exit 1
fi
echo "    ✓ 本地服务端运行中 (http://localhost:$PORT)"

echo "==> 2/3 建立 serveo 公网隧道"
ssh -o ServerAliveInterval=60 -o StrictHostKeyChecking=no \
    -o ExitOnForwardFailure=yes \
    -R 80:localhost:$PORT serveo.net 2>/dev/null &
SSH_PID=$!
sleep 4

echo "==> 3/3 获取公网地址"
URL=$(curl -s "http://localhost:$PORT" -o /dev/null -w '' || true)
# serveo 打印的地址从 ssh 输出中取；此处提示用户查看上方 Forwarding 行
echo ""
echo "======================================================"
echo "  公网地址请看上面 'Forwarding HTTP traffic from' 那行"
echo "  例：https://xxxx.serveousercontent.com"
echo ""
echo "  App 端配置：设置 → 服务器 → 填入上面的 https 地址"
echo "  验证：curl https://<地址>/healthz → ok"
echo "  停止：Ctrl+C"
echo "======================================================"
wait $SSH_PID
