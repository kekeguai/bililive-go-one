# bili

基于 [bililive-go](https://github.com/bililive-go/bililive-go) 的 Linux 一键部署与管理脚本。安装时自动配置 ffmpeg 与 bililive-go，可自定义 Web/RPC 监听端口，安装后通过 `bili` 命令进行启动、停止、重启、状态查看、版本更新、修改端口和查看日志。

## 特性

- **完整安装**：自动安装 ffmpeg 与 bililive-go，流程与[官方 Install Linux 文档](https://github.com/bililive-go/bililive-go/wiki/Install-Linux)一致
- **一键部署**：自动下载 GitHub Releases 中对应架构的预编译二进制，无需编译环境
- **多包管理器**：支持 apt、dnf、yum、pacman
- **自定义端口**：安装时交互输入监听端口（默认 `8080`），并校验端口范围与占用情况
- **命令行管理**：安装后直接使用 `bili` 命令进行服务管理
- **版本更新**：对比 GitHub 最新 Release，支持一键更新，失败自动回滚
- **开机自启**：有 systemd 时注册为服务，异常退出自动拉起
- **无 systemd 兼容**：自动退化为后台进程方式运行
- **防火墙联动**：自动检测 ufw / firewalld 并放行或关闭对应端口

## 系统要求

- Debian / Ubuntu / CentOS / RHEL / Rocky / AlmaLinux / Fedora / Arch Linux
- root 权限（或 sudo）
- 可访问 GitHub（用于获取版本信息、下载脚本与二进制）
- 可访问系统软件源（用于安装 ffmpeg）
- 支持架构：`x86_64`、`aarch64`、`armv7l`、`armv6l`、`i386`

## 安装

### 方式一：一行命令安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/kekeguai/bililive-go-one/refs/heads/main/bili.sh -o bili.sh && sudo bash bili.sh install
```

### 方式二：使用 wget 下载

```bash
wget -O bili.sh https://raw.githubusercontent.com/kekeguai/bililive-go-one/refs/heads/main/bili.sh
sudo bash bili.sh install
```

### 方式三：手动粘贴保存

```bash
nano bili.sh      # 粘贴脚本内容后 Ctrl+O 保存，Ctrl+X 退出
sudo bash bili.sh install
```

安装过程中会提示输入监听端口（例如 `65510`，直接回车则使用 `8080`）。安装完成后，脚本会被复制到 `/usr/local/sbin/bili`，之后即可直接使用 `bili` 命令。

### ffmpeg 安装说明

脚本会根据系统包管理器自动安装 ffmpeg，等同于官方文档中的以下命令：

| 系统 | 命令 |
| --- | --- |
| Debian / Ubuntu | `apt-get install -y ffmpeg` |
| Fedora | `dnf install -y ffmpeg` |
| CentOS / RHEL / Rocky / AlmaLinux | `yum install -y ffmpeg` |
| Arch Linux | `pacman -S --noconfirm ffmpeg` |

安装后会执行 `ffmpeg -version` 校验，失败则中止安装。

**CentOS / RHEL 系注意**：默认软件源通常没有 ffmpeg，需要先启用 EPEL 与 RPM Fusion。若脚本提示安装失败，可手动执行：

```bash
sudo yum install -y epel-release
# 然后参考 https://rpmfusion.org/Configuration 添加 RPM Fusion 源
sudo yum install -y ffmpeg
```

Fedora 下若 dnf 无法直接安装 ffmpeg，同样需要先启用 RPM Fusion Free 源。

## 命令一览

| 命令 | 说明 |
| --- | --- |
| `bili install` | 安装 ffmpeg 与 bililive-go，交互输入监听端口 |
| `bili start` | 启动服务 |
| `bili stop` | 停止服务 |
| `bili restart` | 重启服务 |
| `bili status` | 查看运行状态、程序版本、ffmpeg 版本、端口及访问地址 |
| `bili port [新端口]` | 修改 Web/RPC 监听端口，不填则交互输入 |
| `bili update` | 检查并更新到最新版本 |
| `bili log` | 查看运行日志 |
| `bili uninstall` | 卸载 bililive-go（会删除配置与录制数据，需确认，不删除 ffmpeg） |

## 使用示例

```bash
sudo bili status          # 查看状态、版本、ffmpeg 与访问地址
sudo bili restart         # 重启服务
sudo bili stop            # 停止服务
sudo bili start           # 启动服务
sudo bili port 65510      # 修改监听端口
sudo bili update          # 检查并更新版本
sudo bili log             # 查看日志
sudo bili uninstall       # 卸载
```

## 访问 Web 管理页面

执行 `bili status` 或安装完成后会输出访问地址，格式如下：

```
Web 管理页面 : http://服务器IP:65510
配置文件     : /opt/bililive-go/config.yml
数据目录     : /opt/bililive-go/data
```

在浏览器中打开上述地址即可进入 bililive-go 管理界面。

## 目录与文件

| 路径 | 说明 |
| --- | --- |
| `/usr/local/sbin/bili` | 管理脚本本体 |
| `/opt/bililive-go/bililive-go` | bililive-go 可执行文件 |
| `/opt/bililive-go/config.yml` | 配置文件 |
| `/opt/bililive-go/data` | 录制数据目录 |
| `/opt/bililive-go/version` | 当前安装版本记录 |
| `/opt/bililive-go/bililive-go.log` | 运行日志（无 systemd 时及 systemd 输出日志） |
| `/etc/systemd/system/bililive-go.service` | systemd 服务文件 |

## 注意事项

1. **ffmpeg 为必需组件**：录制与转码依赖 ffmpeg，缺少时服务可能无法正常工作。
2. **云服务器**：阿里云、腾讯云、AWS 等需在安全组中手动放行所选端口，脚本只能处理系统本机防火墙。
3. **端口选择**：建议使用 1024–65535 之间未被占用的端口，例如 `65510`。
4. **配置修改**：脚本生成的 `config.yml` 为最小配置。Cookie、录制规则、推送等可在 Web 管理页面中设置，也可直接编辑配置文件后执行 `bili restart`。
5. **RPC 与 Web 共用端口**：Web 管理页面与 RPC 使用同一个 `rpc.port` 配置项，修改端口即同时修改两者。
6. **更新机制**：`bili update` 会先备份当前二进制，下载失败时自动回滚；更新期间服务会短暂停止。
7. **下载文件名**：脚本按 `bililive-go_<架构>_<版本>.tar.gz` 的命名规则下载。若官方发布的文件名有变化，需同步修改脚本中 `download_binary` 函数的 URL 规则。
8. **卸载不删除 ffmpeg**：ffmpeg 是系统组件，可能被其他程序使用，如需删除请手动执行包管理器命令。
9. **无 systemd 环境**：服务以后台进程运行，不会开机自启。

## 常见问题

**安装时 ffmpeg 安装失败？**
按提示在 CentOS / RHEL 或 Fedora 上启用 EPEL / RPM Fusion 源后重试，或先手动执行 `ffmpeg -version` 确认安装情况。

**安装后无法访问 Web 页面？**
依次检查：`bili status` 中服务是否为「运行中」；云安全组是否放行端口；系统防火墙（`ufw status` 或 `firewall-cmd --list-ports`）是否放行。

**服务启动失败？**
执行 `bili log` 查看日志，并确认端口未被其他程序占用，例如 `ss -lnt | grep 65510`。

**提示无法获取最新版本？**
通常是 GitHub 访问受限或 API 请求频率超限，稍后重试，或检查服务器网络。

**如何彻底删除？**
执行 `sudo bili uninstall` 删除 bililive-go；如需同时删除 ffmpeg，请使用对应包管理器卸载。

## 免责声明

本项目仅供学习和个人管理使用。请遵守所在地区的法律法规及相关平台的服务条款，尊重主播与内容版权，不要用于侵权或违规用途。
