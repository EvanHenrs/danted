#!/bin/bash

# ===================== 参数检查 =====================
if [ "$#" -lt 3 ]; then
    echo "❌ 使用方法: $0 <IP> <PORT> \"<USER1:PASSWORD1 USER2:PASSWORD2>\""
    echo "示例: $0 172.17.62.107 1080 \"user1:qwertyuiop123 user2:asdfghjkl456\""
    exit 1
fi

# 读取外部参数
IP="$1"
PORT="$2"
USERS=($3)  # 用户名和密码的数组

DANTE_CONFIG="/etc/danted.conf"
DANTE_PAM="/etc/pam.d/sockd"

echo "📌 代理监听 IP: $IP"
echo "📌 代理监听端口: $PORT"
echo "📌 用户列表: ${USERS[@]}"

# ===================== 安装 Dante Socks5 =====================
echo "[1] 更新系统并安装 Dante"
sudo apt update && sudo apt install -y dante-server

# ===================== 配置 Dante Socks5 =====================
echo "[2] 配置 Dante 代理服务"

# 生成 danted.conf
cat <<EOF | sudo tee $DANTE_CONFIG > /dev/null
logoutput: syslog

# 监听 IP 和端口
internal: $IP port = $PORT
external: $IP

# 认证方式：用户名/密码
socksmethod: username

# 运行用户
user.privileged: root
user.notprivileged: nobody

# 允许所有客户端连接
client pass {
    from: 0/0 to: 0/0
    log: connect disconnect
}

# 允许 Socks5 代理通过
socks pass {
    from: 0/0 to: 0/0
    socksmethod: username
    log: connect disconnect
}
EOF

# ===================== 配置 PAM 认证 =====================
echo "[3] 配置 PAM 认证"
cat <<EOF | sudo tee $DANTE_PAM > /dev/null
auth required pam_unix.so
account required pam_unix.so
EOF

# ===================== 创建用户和密码 =====================
echo "[4] 创建 Socks5 用户"
for user in "${USERS[@]}"; do
    USERNAME=$(echo $user | cut -d':' -f1)
    PASSWORD=$(echo $user | cut -d':' -f2)

    # 创建用户
    sudo useradd -r -s /bin/false $USERNAME 2>/dev/null
    echo "$USERNAME:$PASSWORD" | sudo chpasswd
    echo "    ✅ 用户 $USERNAME 创建成功！"
done

# ===================== 启动 Dante 并检查状态 =====================
echo "[5] 启动 Dante 代理服务"
sudo systemctl enable danted
sudo systemctl restart danted
sudo systemctl status danted --no-pager --lines=5

# ===================== 确保端口监听 =====================
echo "[6] 检查代理端口监听状态"
sudo netstat -tulnp | grep sockd || sudo ss -tulnp | grep sockd

# ===================== 测试代理 =====================
TEST_USER=$(echo ${USERS[0]} | cut -d':' -f1)
TEST_PASS=$(echo ${USERS[0]} | cut -d':' -f2)
PUBLIC_IP=$(curl -s ifconfig.me)

echo "[7] 测试 Socks5 代理访问外网"
curl --proxy socks5://$TEST_USER:$TEST_PASS@$PUBLIC_IP:$PORT myip.ipip.net

echo "🎉 Dante Socks5 代理安装完成！"
echo "📌 代理地址：$IP:$PORT"
echo "🔑 账号列表："
for user in "${USERS[@]}"; do
    echo "   - $(echo $user | cut -d':' -f1) / $(echo $user | cut -d':' -f2)"
done
