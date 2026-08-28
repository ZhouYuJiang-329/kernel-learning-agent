@echo off
chcp 65001 >nul
rem 停止 dashboard（Windows 版，对应 stop.sh）
setlocal
set "PORT=7788"

set "FOUND="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /R "TCP.*:%PORT%.*LISTENING"') do (
    set "FOUND=1"
    taskkill /PID %%p /F >nul 2>&1
    if not errorlevel 1 (
        echo Dashboard 已关闭（PID %%p）
    ) else (
        echo 无法结束进程 PID %%p，请手动检查
    )
)

if not defined FOUND echo Dashboard 未在运行
