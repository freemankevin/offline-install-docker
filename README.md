# offline-install-docker

[![更新状态](https://github.com/freemankevin/offline-install-docker/actions/workflows/update.yml/badge.svg)](https://github.com/freemankevin/offline-install-docker/actions/workflows/update.yml)

🚀 自动化维护的 Docker 离线安装包，支持 x86_64 和 ARM64 架构。

## ✨ 特性

- 🤖 **自动更新**: GitHub Actions 每周自动检测并更新 Docker 版本
- 🏗️ **多架构支持**: 同时支持 x86_64 (AMD64) 和 aarch64 (ARM64)
- 📦 **完整打包**: 包含 Docker Engine、Docker Compose 和所有必需配置
- 🔒 **安全验证**: 提供 SHA256 校验和文件
- 📝 **详细文档**: 包含完整的安装和使用说明
- 🎯 **开箱即用**: 一键安装脚本，自动检测系统架构

## 🎯 适用场景

- 🚫 **无外网环境**: 内网服务器、隔离网络环境
- 🏢 **企业部署**: 批量部署 Docker 到多台服务器
- 🇨🇳 **国产化适配**: 支持麒麟、统信等国产操作系统
- 💻 **ARM 服务器**: 华为鲲鹏、飞腾等 ARM 架构服务器

## 📁 目录结构

```shell
offline-install-docker/
├── .github/
│   └── workflows/
│       └── update-docker.yml          # GitHub Actions 自动更新配置
├── scripts/
│   ├── update.py               # Python 更新脚本
│   ├── install.sh              # Docker 安装脚本
│   ├── uninstall.sh            # Docker 卸载脚本
├── services/
│   ├── daemon.json                    # Docker 配置文件
│   ├── docker.service                 # Docker systemd 服务
│   ├── docker.socket                  # Docker socket 配置
│   └── containerd.service             # containerd systemd 服务
├── packages/                          # 自动生成的离线包目录
│   ├── docker-*.tgz
│   ├── docker-compose-linux-*
│   ├── VERSION.json
│   └── SHA256SUMS
├── .gitignore                         # Git 忽略配置
├── README.md                          # 项目说明文档
```

## 📦 快速开始

### 下载离线包

前往 [Releases 页面](https://github.com/freemankevin/offline-install-docker/releases) 下载最新版本。

### 安装步骤

1. **解压下载的包**
   ```bash
   tar -xzf docker-offline-vX.X.X.tar.gz
   cd docker-offline-vX.X.X
   ```

2. **安装 Docker**
   ```bash
   bash ./packages/scripts/install.sh
   ```

3. **验证安装**
   ```bash
   docker --version
   docker-compose --version
   ```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！