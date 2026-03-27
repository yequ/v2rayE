# v2rayE

一个基于 SwiftUI 构建的 macOS 原生 V2Ray 客户端，提供简洁易用的图形化界面。

## ✨ 功能特性

- 📱 **订阅管理**：支持添加、更新和管理多个 V2Ray 订阅源。
- 🌍 **节点选择**：直观的节点列表，支持灵活切换代理节点。
- 🔌 **代理模式**：支持全局代理和 PAC（自动代理配置）模式。
- 🌐 **端口配置**：支持自定义 HTTP 和 SOCKS5 代理端口（默认 1087 / 1080）。
- 🚀 **自动连接**：支持应用启动时自动连接上次使用的节点。
- 📊 **实时延迟**：直观显示当前连接节点的网络延迟。
- 🔍 **内核自动发现**：智能查找系统中的 V2Ray 可执行文件，无需繁琐配置。

## 🚀 快速开始

### 1. 安装 V2Ray 内核

v2rayE 作为一个图形化客户端，依赖于 V2Ray 核心程序运行。应用启动时会按以下顺序自动查找 `v2ray` 可执行文件：

1. `~/Library/Application Support/v2rayE/core/v2ray` (推荐)
2. `/opt/homebrew/bin/v2ray` (Homebrew 默认路径)
3. `/usr/local/bin/v2ray`
4. `/usr/bin/v2ray`
5. 其他常见安装目录

> **提示**：如果系统中未安装 V2Ray，应用会提示您将内核文件放置到推荐的默认目录中。

### 2. 配置路由数据文件

为了让 V2Ray 正常进行路由分流，请将 `geoip.dat` 和 `geosite.dat` 文件放置到核心目录下：

```bash
~/Library/Application Support/v2rayE/core/
```

### 3. PAC 模式配置 (可选)

如果您使用 PAC 模式，应用会读取以下路径的 PAC 脚本文件：

```bash
~/Library/Application Support/v2rayE/proxy.js
```

您可以根据需要自定义此文件，以控制更精细的代理规则。

## 📁 目录结构与配置

所有的应用数据和配置文件均统一存储在以下目录：

```bash
~/Library/Application Support/v2rayE/
```

**目录说明：**
- `app-config.json`：v2rayE 的应用配置文件（包含订阅、设置等）。
- `core/v2ray`：V2Ray 核心可执行文件。
- `core/`：V2Ray 运行所需的数据文件目录（如 `geoip.dat`, `geosite.dat`）。
- `proxy.js`：PAC 模式使用的自动代理规则文件。

## 🛠 开发指南

本项目使用 Swift Package Manager (SPM) 进行依赖管理和构建。

### 系统要求

- macOS 13.0+
- Swift 5.9+
- Xcode 15.0+ (推荐)

### 运行项目

在项目根目录下执行以下命令即可编译并运行：

```bash
swift run
```

## 📄 许可证

本项目基于 MIT License 开源。
