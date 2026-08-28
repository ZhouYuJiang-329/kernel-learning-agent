#!/usr/bin/env bash
PORT=7788

PID=$(lsof -ti :$PORT 2>/dev/null)
if [ -n "$PID" ]; then
    kill $PID
    echo "Dashboard 已关闭（PID $PID）"
else
    echo "Dashboard 未在运行"
fi
