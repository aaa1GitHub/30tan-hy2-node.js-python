#!/bin/bash
set -euo pipefail

echo "=============================================="
echo "     VLESS + TCP + Reality 一键部署脚本"
echo "       优化修复版（端口不再固定、无 -1）"
echo "=============================================="

# =============================
# 生成随机 UUID
# =============================
UUID=$(cat /proc/sys/kernel/random/uuid)

# =============================
# 生成随机端口（避开 1–29999）
# =============================
get_random_port() {
    while true; do
        PORT=$(shuf -i 30000-60000 -n 1)
        ss -tulpn | grep -q ":$PORT " || break
    done
    echo "$PORT"
}
PORT=$(get_random_port)

echo "已选择随机端口: $PORT"
echo "UUID: $UUID"

# =============================
# 下载最新 Xray
# =============================
if [[ ! -f "./xray" ]]; then
    echo "正在下载 Xray 最新版本..."
    URL=$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest |
          grep browser_download_url | grep linux-64.zip | cut -d\" -f4)

    curl -L -o xray.zip "$URL"
    unzip -j xray.zip xray -d .
    rm -f xray.zip
    chmod +x xray
fi

# =============================
# 生成 Reality Keys（正确格式）
# =============================
KEYS=$(./xray x25519)
PRIV=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
PUB=$(echo "$KEYS"  | grep PublicKey  | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)
MASQ="www.cloudflare.com"

echo "Reality PublicKey: $PUB"
echo "Reality ShortId: $SHORT_ID"

# =============================
# 写入 Xray 配置
# =============================
cat > reality.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$UUID",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$MASQ:443",
        "serverNames": ["$MASQ"],
        "privateKey": "$PRIV",
        "publicKey": "$PUB",
        "shortIds": ["$SHORT_ID"],
        "fingerprint": "chrome",
        "spiderX": "/"
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# =============================
# 防火墙放行端口
# =============================
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "检测到 firewalld，放行端口..."
    firewall-cmd --add-port=$PORT/tcp --permanent || true
    firewall-cmd --reload || true
elif command -v ufw >/dev/null 2>&1; then
    echo "检测到 ufw，放行端口..."
    ufw allow $PORT/tcp || true
fi

# =============================
# 结束旧进程 & 后台运行
# =============================
pkill -f "xray run" >/dev/null 2>&1 || true

echo "启动 Xray Reality 服务..."
nohup ./xray run -c reality.json >/dev/null 2>&1 &

sleep 1

# =============================
# 获取出口 IP
# =============================
IP=$(curl -s https://api64.ipify.org || echo "服务器IP获取失败")

# =============================
# 输出节点链接
# =============================
echo ""
echo "============== Reality 节点 =============="
LINK="vless://$UUID@$IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$MASQ&fp=chrome&pbk=$PUB&sid=$SHORT_ID&type=tcp&spx=/#Reality-Vision"

echo "$LINK"
echo "========================================="
echo "部署完成！Reality 不需要反代 / CF 代理（需关闭）"

