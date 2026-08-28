#!/usr/bin/env bash
# 启动 dashboard，已在运行则直接打开浏览器
PORT=7788
MAX_WAIT=10  # 最多等待秒数

wait_for_port() {
    local elapsed=0
    while ! (echo >/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; do
        sleep 0.2
        elapsed=$(echo "$elapsed + 0.2" | bc)
        if (( $(echo "$elapsed >= $MAX_WAIT" | bc -l) )); then
            echo "错误：Dashboard 启动超时（${MAX_WAIT}s），请检查 /tmp/kernel-dashboard.log"
            return 1
        fi
    done
    return 0
}

if (echo >/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
    echo "Dashboard 已在运行：http://localhost:$PORT"
else
    cd "$(dirname "$0")"
    nohup python3 server.py > /tmp/kernel-dashboard.log 2>&1 &
    echo -n "等待 Dashboard 启动..."
    if wait_for_port; then
        echo " 就绪"
        echo "Dashboard 已启动：http://localhost:$PORT"
    else
        exit 1
    fi
fi

# WSL2：优先用 localhost（需要 Windows localhostForwarding=true，默认已开启）
# 若浏览器打不开，备用 Windows host IP 见 /etc/resolv.conf nameserver
URL="http://localhost:$PORT"

if command -v explorer.exe >/dev/null 2>&1; then
    explorer.exe "$URL" &
elif command -v wslview >/dev/null 2>&1; then
    wslview "$URL"
else
    echo "请在浏览器中手动打开：$URL"
fi
