@echo off
chcp 65001 >nul
rem 启动 dashboard，已在运行则直接打开浏览器（Windows 版，对应 start.sh）
setlocal EnableDelayedExpansion
set "PORT=7788"
rem 最多等待秒数
set /a "MAX_WAIT=10"
set "DIR=%~dp0"
set "LOGFILE=%DIR%dashboard.log"

cd /d "%DIR%"

rem 检查 python 是否可用
python --version >nul 2>&1
if errorlevel 1 (
    echo 错误：未找到 python，请确认已安装并加入 PATH
    exit /b 1
)

rem 端口是否已在监听
netstat -ano | findstr /R "TCP.*:%PORT%.*LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo Dashboard 已在运行：http://localhost:%PORT%
    goto :open_browser
)

rem 后台启动 server.py，输出写入日志
start "KernelDashboard" /b cmd /c "python server.py >> "%LOGFILE%" 2>&1"

<nul set /p "=等待 Dashboard 启动..."
set /a "elapsed=0"
:wait_loop
netstat -ano | findstr /R "TCP.*:%PORT%.*LISTENING" >nul 2>&1
if not errorlevel 1 goto :ready
%SystemRoot%\System32\ping.exe -n 2 127.0.0.1 >nul
set /a "elapsed+=1"
if !elapsed! GEQ %MAX_WAIT% (
    echo.
    echo 错误：Dashboard 启动超时（%MAX_WAIT%s），请检查 %LOGFILE%
    exit /b 1
)
goto :wait_loop

:ready
echo 就绪
echo Dashboard 已启动：http://localhost:%PORT%

:open_browser
start "" "http://localhost:%PORT%"
exit /b 0
