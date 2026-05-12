# Intra Ferry

内渡是 Intra Ferry 的中文名。它是一个 macOS 菜单栏应用，用于在可信内网里的两台 Mac 之间传输文件、文件夹和剪贴板内容。

当前实现偏原型和本地测试，应用名、SwiftPM 包名、target 和源码目录继续使用 `IntraFerry` / `Ferry`。

## 功能

- 菜单栏常驻入口：状态栏显示 `Ferry`。
- 双机点对点通信：一台 Mac 通过另一台 Mac 的 IP、端口和共享口令连接。
- 授权接收路径：只允许对端访问你在设置里授权的目录。
- 文件和文件夹传输：在传输窗口选择对端目录后拖入文件或文件夹。
- 对端路径浏览：支持刷新、进入目录、返回上一级、选择当前路径。
- 剪贴板同步：支持文本、图片和 Finder 文件剪贴板的基础同步。
- 本地开发口令存储：当前版本使用本地 `secrets.json`，避免调试版反复触发 Keychain 授权弹窗。

## 环境要求

- macOS 14 或更高版本。
- Swift 6.1 工具链。
- 仅构建和打包：Command Line Tools 通常足够。
- 跑 `swift test`：需要完整 Xcode，因为测试依赖 XCTest。

如果本机只有 Command Line Tools，`swift test` 可能报：

```text
no such module 'XCTest'
```

安装完整 Xcode 后可执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
swift test
```

## 快速开始

构建：

```bash
swift build
```

打包成本地 macOS app：

```bash
scripts/package-macos-app.sh
open build/IntraFerry.app
```

应用启动后不会出现在 Dock，入口在菜单栏右上角的 `Ferry`。

## 双机配置

两台 Mac 都需要运行 Intra Ferry，并互相填写对方的信息。

假设：

- Mac A IP：`192.168.1.10`
- Mac B IP：`192.168.1.11`
- 端口固定使用：`49491`
- 共享口令两台保持一致，例如：`test-token`

Mac A 设置：

```text
本机名称：日常电脑
对端地址：192.168.1.11
对端端口：49491
共享口令：test-token
允许接收路径：/Users/你的用户名
```

Mac B 设置：

```text
本机名称：任务电脑
对端地址：192.168.1.10
对端端口：49491
共享口令：test-token
允许接收路径：/Users/你的用户名
```

保存成功后，菜单栏状态会显示正在监听端口 `49491`。

## 使用方式

### 文件和文件夹

1. 点击菜单栏 `Ferry`。
2. 打开传输窗口。
3. 在对端路径浏览区点击 `刷新`。
4. 进入目标目录，点击 `选择当前路径`。
5. 把文件或文件夹拖到拖拽区。

### 剪贴板

两台电脑都保存配置并启用剪贴板同步后：

1. 在一台 Mac 上复制文本、图片或 Finder 文件。
2. 在另一台 Mac 上直接粘贴。

剪贴板同步可在菜单栏弹窗或设置里关闭。

## 项目结构

```text
Package.swift
Sources/
  IntraFerryCore/      核心库：模型、配置、路径授权、传输、HTTP、剪贴板和运行时
  IntraFerryApp/       macOS 菜单栏应用：AppKit/SwiftUI 窗口和状态管理
Tests/
  IntraFerryCoreTests/ 核心库测试
docs/
  manual-testing.md    手工测试清单
scripts/
  package-macos-app.sh 本地 app 打包脚本
```

## 本地数据

当前版本会把配置和共享口令写到：

```text
~/Library/Application Support/IntraFerry/config.json
~/Library/Application Support/IntraFerry/secrets.json
```

`secrets.json` 是为了本地调试方便使用的开发期存储。正式发布前应切回 Keychain 或更严格的凭据存储方案。

## 常见问题

### 为什么要填共享口令？

共享口令用于两台 Mac 之间互相认证。对端发起目录浏览、文件上传或剪贴板写入时，接收端会校验口令，避免同一内网里的其他设备随意访问。

### 为什么端口固定是 49491？

当前原型的本机监听端口固定为 `49491`。两台电脑的对端端口都填 `49491` 即可。

### 传输目标为什么必须是目录？

文件和文件夹会被发送到你在传输窗口里选择的对端目录。文件项只展示，不作为目标路径。

### 另一台电脑怎么安装？

推送到远程仓库后，在另一台电脑执行：

```bash
git clone <远程仓库地址>
cd intra-ferry
scripts/package-macos-app.sh
open build/IntraFerry.app
```

## 验证

本机可运行：

```bash
swift build
scripts/package-macos-app.sh
```

完整自动测试需要 Xcode：

```bash
swift test
```

更多双机验收步骤见 [docs/manual-testing.md](docs/manual-testing.md)。
