#!/bin/bash
# =====================================================================
# bili - bililive-go 一键部署与管理脚本
# 项目地址: https://github.com/bililive-go/bililive-go
# 支持系统: Debian / Ubuntu / CentOS / RHEL / Rocky / AlmaLinux / Fedora / Arch
# 运行方式: sudo bash bili.sh install
# =====================================================================

set -u

APP_NAME="bililive-go"
REPO="bililive-go/bililive-go"
INSTALL_DIR="/opt/bililive-go"
BIN_PATH="${INSTALL_DIR}/bililive-go"
CONF_FILE="${INSTALL_DIR}/config.yml"
DATA_DIR="${INSTALL_DIR}/data"
LOG_FILE="${INSTALL_DIR}/bililive.log"
PID_FILE="${INSTALL_DIR}/bililive.pid"
VER_FILE="${INSTALL_DIR}/version"
SCRIPT_DST="/usr/local/sbin/bili"
SERVICE_NAME="bililive-go"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

need_root() { [[ $EUID -eq 0 ]] || err "请使用 root 或 sudo 运行"; }
has_systemd() { command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; }

# ---------- 工具函数 ----------
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1024 && $1 <= 65535 )); }

port_in_use() {
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1$"
}

get_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "linux_amd64" ;;
        aarch64|arm64) echo "linux_arm64" ;;
        armv7l|armv7)  echo "linux_armv7" ;;
        armv6l)        echo "linux_armv6" ;;
        i386|i686)     echo "linux_386" ;;
        *) err "不支持的架构: $(uname -m)" ;;
    esac
}

get_latest_version() {
    local v
    v=$(curl -fsSL --max-time 15 "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
    [[ -n "$v" ]] || err "无法获取最新版本信息，请检查网络或 GitHub 访问"
    echo "$v"
}

get_local_version() { [[ -f "$VER_FILE" ]] && cat "$VER_FILE" || echo "未安装"; }

get_port() {
    if [[ -f "$CONF_FILE" ]]; then
        grep -E '^\s*port:' "$CONF_FILE" | head -1 | awk '{print $2}'
    else
        echo "-"
    fi
}

get_ip() { curl -s4 --max-time 5 ifconfig.me || curl -s4 --max-time 5 ip.sb || echo "服务器IP"; }

# ---------- 依赖与 ffmpeg ----------
install_deps() {
    info "安装基础依赖..."
    if command -v apt-get &>/dev/null; then
        apt-get update -y >/dev/null
        apt-get install -y curl tar ca-certificates iproute2 >/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y curl tar ca-certificates iproute >/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y curl tar ca-certificates iproute >/dev/null
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm --needed curl tar ca-certificates iproute2 >/dev/null
    else
        warn "未识别的包管理器，请确保已安装 curl、tar"
    fi
}

check_ffmpeg() {
    command -v ffmpeg &>/dev/null && ffmpeg -version &>/dev/null
}

get_ffmpeg_version() {
    if check_ffmpeg; then
        ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}'
    else
        echo "未安装"
    fi
}

install_ffmpeg() {
    if check_ffmpeg; then
        info "ffmpeg 已安装: $(get_ffmpeg_version)"
        return
    fi

    info "安装 ffmpeg..."
    if command -v apt-get &>/dev/null; then
        apt-get install -y ffmpeg || err "ffmpeg 安装失败，请检查 apt 源后重试"
    elif command -v dnf &>/dev/null; then
        if ! dnf install -y ffmpeg; then
            warn "dnf 无法直接安装 ffmpeg，通常需要先启用 RPM Fusion："
            warn "  sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm"
            warn "  sudo dnf install -y ffmpeg"
            err "ffmpeg 安装失败"
        fi
    elif command -v yum &>/dev/null; then
        if ! yum install -y ffmpeg; then
            warn "yum 无法直接安装 ffmpeg，CentOS / RHEL 系通常需要先启用 EPEL 与 RPM Fusion："
            warn "  sudo yum install -y epel-release"
            warn "  然后参考 https://rpmfusion.org/Configuration 添加 RPM Fusion 源"
            warn "  sudo yum install -y ffmpeg"
            err "ffmpeg 安装失败"
        fi
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm --needed ffmpeg || err "ffmpeg 安装失败"
    else
        err "不支持的包管理器，请手动安装 ffmpeg 后重试"
    fi

    check_ffmpeg || err "ffmpeg 安装后仍不可用，请手动检查"
    info "ffmpeg 安装成功: $(get_ffmpeg_version)"
}

# ---------- 下载与安装二进制 ----------
download_binary() {
    local tag="$1" arch ver url tmp found
    arch=$(get_arch)
    ver="${tag#v}"
    url="https://github.com/${REPO}/releases/download/${tag}/bililive-go_${arch}_${ver}.tar.gz"
    tmp=$(mktemp -d)
    info "下载 ${APP_NAME} ${tag} (${arch})..."
    curl -fL --retry 3 --max-time 300 -o "$tmp/pkg.tar.gz" "$url" || { rm -rf "$tmp"; err "下载失败: $url"; }
    tar -xzf "$tmp/pkg.tar.gz" -C "$tmp" || { rm -rf "$tmp"; err "解压失败"; }
    found=$(find "$tmp" -type f -name 'bililive-go' | head -1)
    [[ -n "$found" ]] || { rm -rf "$tmp"; err "压缩包中未找到 bililive-go 可执行文件"; }
    install -m 755 "$found" "$BIN_PATH"
    echo "$tag" > "$VER_FILE"
    rm -rf "$tmp"
}

write_config() {
    local port="$1"
    mkdir -p "$DATA_DIR"
    cat > "$CONF_FILE" <<EOF
rpc:
  enable: true
  port: ${port}
  host: 0.0.0.0
  ssl_cert_file: ""
  ssl_key_file: ""
  token: ""
debug: false
interval: 20
out_put_path: ${DATA_DIR}
log:
  out_put_file: true
  save_last_days: 7
EOF
}

write_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=bililive-go live recorder
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_PATH} --config ${CONF_FILE}
Restart=on-failure
RestartSec=5
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# 无 systemd 时的后台进程管理
bg_start() {
    cd "$INSTALL_DIR" || return 1
    nohup "$BIN_PATH" --config "$CONF_FILE" >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
}
bg_stop() {
    [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
    pkill -f "$BIN_PATH" 2>/dev/null
}
bg_running() { pgrep -f "$BIN_PATH" >/dev/null 2>&1; }

svc_start()   { if has_systemd; then systemctl start "$SERVICE_NAME"; else bg_start; fi; }
svc_stop()    { if has_systemd; then systemctl stop "$SERVICE_NAME"; else bg_stop; fi; }
svc_restart() { if has_systemd; then systemctl restart "$SERVICE_NAME"; else bg_stop; bg_start; fi; }
svc_running() {
    if has_systemd; then systemctl is-active --quiet "$SERVICE_NAME"; else bg_running; fi
}

# ---------- 防火墙 ----------
open_firewall() {
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$1/tcp" >/dev/null
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="$1/tcp" >/dev/null
        firewall-cmd --reload >/dev/null
    else
        warn "未检测到活动防火墙，请自行确认端口 $1 已放行（云服务器需检查安全组）"
    fi
}

close_firewall() {
    local p=$1
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw delete allow "$p/tcp" >/dev/null 2>&1
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --remove-port="$p/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
}

print_access() {
    local ip; ip=$(get_ip)
    echo "--------------------------------------------"
    echo " Web 管理页面 : http://${ip}:$1"
    echo " 配置文件     : ${CONF_FILE}"
    echo " 数据目录     : ${DATA_DIR}"
    echo "--------------------------------------------"
}

# ---------- 子命令 ----------
cmd_install() {
    need_root
    [[ -f "$BIN_PATH" ]] && err "已安装，如需重装请先执行 bili uninstall"
    install_deps
    install_ffmpeg
    mkdir -p "$INSTALL_DIR"

    local port
    while true; do
        read -rp "请输入 Web/RPC 监听端口 [默认 8080]: " port
        port=${port:-8080}
        if ! valid_port "$port"; then
            warn "端口需为 1024-65535 之间的数字"; continue
        fi
        if port_in_use "$port"; then
            warn "端口 $port 已被占用，请更换"; continue
        fi
        break
    done

    local tag; tag=$(get_latest_version)
    download_binary "$tag"
    write_config "$port"

    if [[ "$(readlink -f "$0")" != "$SCRIPT_DST" ]]; then
        install -m 755 "$0" "$SCRIPT_DST"
    fi

    if has_systemd; then
        write_service
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    fi
    svc_start
    sleep 2

    if svc_running; then
        open_firewall "$port"
        info "安装完成！版本: $tag"
        print_access "$port"
        echo "管理命令: bili {start|stop|restart|status|update|port|log|uninstall}"
    else
        err "启动失败，请执行 bili log 查看日志"
    fi
}

cmd_start() {
    need_root; [[ -f "$BIN_PATH" ]] || err "未安装"
    if svc_running; then info "已在运行"; return; fi
    svc_start; sleep 1
    if svc_running; then info "已启动"; else err "启动失败，请执行 bili log 查看"; fi
}

cmd_stop() {
    need_root
    if ! svc_running; then info "服务未运行"; return; fi
    svc_stop; info "已停止"
}

cmd_restart() {
    need_root; [[ -f "$BIN_PATH" ]] || err "未安装"
    svc_restart; sleep 1
    if svc_running; then info "已重启"; else err "重启失败，请执行 bili log 查看"; fi
}

cmd_status() {
    local st="已停止"; svc_running && st="运行中"
    echo "--------------------------------------------"
    echo " 服务状态 : $st"
    echo " 程序版本 : $(get_local_version)"
    echo " FFmpeg   : $(get_ffmpeg_version)"
    echo " Web 端口 : $(get_port)"
    echo " 安装目录 : $INSTALL_DIR"
    echo "--------------------------------------------"
    [[ "$st" == "运行中" ]] && print_access "$(get_port)"
    return 0
}

cmd_port() {
    need_root; [[ -f "$CONF_FILE" ]] || err "未安装"
    local new=${1:-}
    if [[ -z "$new" ]]; then
        read -rp "请输入新端口 (1024-65535): " new
    fi
    valid_port "$new" || err "端口无效: $new"
    port_in_use "$new" && err "端口 $new 已被占用"
    local old; old=$(get_port)
    sed -i -E "0,/^(\s*)port:.*/s//\1port: ${new}/" "$CONF_FILE"
    close_firewall "$old"
    open_firewall "$new"
    cmd_restart
    info "端口已由 $old 修改为 $new"
    print_access "$new"
}

cmd_update() {
    need_root; [[ -f "$BIN_PATH" ]] || err "未安装"
    local latest current
    latest=$(get_latest_version)
    current=$(get_local_version)
    info "当前版本: $current    最新版本: $latest"
    if [[ "$latest" == "$current" ]]; then
        info "已是最新版本"; return
    fi
    read -rp "是否更新到 $latest? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { info "已取消"; return; }

    local was_running=0
    if svc_running; then was_running=1; svc_stop; fi
    cp -f "$BIN_PATH" "${BIN_PATH}.bak"
    if download_binary "$latest"; then
        rm -f "${BIN_PATH}.bak"
        info "已更新到 $latest"
    else
        mv -f "${BIN_PATH}.bak" "$BIN_PATH"
        (( was_running )) && svc_start
        err "更新失败，已回滚到 $current"
    fi
    (( was_running )) && svc_start
    info "更新完成"
}

cmd_log() {
    if has_systemd && [[ ! -f "$LOG_FILE" ]]; then
        journalctl -u "$SERVICE_NAME" -n 100 --no-pager
    else
        tail -n 100 -f "$LOG_FILE"
    fi
}

cmd_uninstall() {
    need_root
    read -rp "确认卸载 bililive-go（配置与录制数据将被删除）? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { info "已取消"; return; }
    local p; p=$(get_port)
    svc_stop
    if has_systemd; then
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    close_firewall "$p"
    rm -rf "$INSTALL_DIR"
    rm -f "$SCRIPT_DST"
    info "bililive-go 已卸载（ffmpeg 为系统组件，未被删除）"
}

usage() {
    cat <<EOF
bili - bililive-go 管理工具

用法:
  bili install            安装 ffmpeg 与 bililive-go，交互输入监听端口
  bili start              启动服务
  bili stop               停止服务
  bili restart            重启服务
  bili status             查看状态、版本、ffmpeg 与访问地址
  bili port [新端口]      修改 Web/RPC 监听端口
  bili update             检查并更新到最新版本
  bili log                查看运行日志
  bili uninstall          卸载 bililive-go（不删除 ffmpeg）
EOF
}

# ---------- 入口 ----------
case "${1:-help}" in
    install)   cmd_install ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    status)    cmd_status ;;
    port)      cmd_port "${2:-}" ;;
    update)    cmd_update ;;
    log)       cmd_log ;;
    uninstall) cmd_uninstall ;;
    *)         usage ;;
esac
