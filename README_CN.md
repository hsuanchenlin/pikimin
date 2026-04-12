# Pikimin

一款 macOS 应用，封装 Android 模拟器用于 Pikmin Bloom 自动行走模拟。安装应用，指向你的 Android SDK，即可开始刷步数——无需了解 Android Studio。

**仅支持 Apple Silicon (M1+)。需要 macOS 14 Sonoma 或更高版本。**

## 功能

- 自动检测已安装的 Android SDK（Android Studio 或 Homebrew）
- 创建和管理 Android 模拟器（Pixel 7，支持 Play Store）
- 模拟真实行走，包含 GPS 移动和步数传感器检测
- 实时仪表盘显示步数、进度、GPS 坐标和行走日志

## 安装

### 1. 安装 Android SDK

**方式 A：Android Studio（推荐）**

从 [developer.android.com/studio](https://developer.android.com/studio) 下载安装。打开一次完成初始设置，然后通过 SDK Manager 安装系统镜像：
- SDK Platforms > Android 16.0 (Baklava) 或 Android 15.0 (API 35)
- 确保勾选 "Google Play ARM 64 v8a System Image"

**方式 B：Homebrew**

```bash
brew install --cask android-commandlinetools
sdkmanager "platform-tools" "emulator" \
  "system-images;android-36.0-Baklava;google_apis_playstore;arm64-v8a"
```

### 2. 安装 Pikimin

从 [Releases](https://github.com/hsuanchenlin/pikimin/releases) 下载 `Pikimin.dmg`，打开后将 `Pikimin.app` 拖入"应用程序"文件夹。

首次启动：右键点击应用 > 打开（用于绕过 Gatekeeper，因为应用使用 ad-hoc 签名）。

### 3. 使用

1. 打开 Pikimin — 自动检测你的 SDK
2. 点击 **Start Emulator** — 等待模拟器启动
3. 在模拟器中打开 Play Store，安装 Pikmin Bloom
4. 设置 GPS 位置（见下方说明）
5. 点击 **Start Walk** — 开始刷步数

### 设置 GPS 位置

开始行走前，需要在模拟器中设置起始位置：

**第 1 步：** 点击模拟器工具栏上的 **`...`**（三个点）按钮，打开 Extended Controls

<img src="docs/images/step1-click-dots.png" width="300">

**第 2 步：** 点击左侧边栏的 **Location**

<img src="docs/images/step2-click-location.png" width="600">

**第 3 步：** 输入经纬度（或在地图上点击），然后点击 **Set Location**

<img src="docs/images/step3-set-location.png" width="600">

行走模拟会以此位置为起点向外行走，后半程返回起点。

## 功能列表

- **SDK 检测** — 自动查找 `~/Library/Android/sdk`（Android Studio）或 `/opt/homebrew/share/android-commandlinetools`（Homebrew）中的 Android SDK
- **模拟器管理** — 一键启动/停止，自动检测已运行的模拟器
- **行走模拟** — 可配置步数，真实步态周期（加速度计 + 陀螺仪），随机 GPS 移动并自动返回
- **实时仪表盘** — 实时步数、进度条、行走阶段、GPS 坐标、已用时间
- **行走日志** — 每 50 步记录一条带时间戳的日志
- **文本输入助手** — 向模拟器发送文本，用于不接受键盘输入的字段（如 Pikmin Bloom 的出生日期）
- **DNS 修复** — 模拟器启动时使用 `-dns-server 8.8.8.8` 避免网络连接问题

## 从源码构建

```bash
cd Pikimin
swift build
./scripts/dev-run.sh    # 构建并以 .app 包启动
./scripts/create-dmg.sh # 构建发布版 DMG
```

## 行走模拟原理

每个步态周期（约 500ms）通过 `adb emu sensor set` 发送 7 次传感器更新：

1. **摆动** — Z 轴降至重力以下
2. **脚跟着地** — Z 轴飙升至 22 m/s²（步数检测的关键触发点）
3. **冲击峰值** — Z 轴达到 25 m/s²
4. **缓冲** — 减速回到重力附近
5. **站立中期** — 重力基线（步数检测器需要这个低谷）
6. **脚尖蹬地** — 较小的二次峰值
7. **静止** — 回到 9.8 m/s²

GPS 坐标每步更新一次（约 1.5m/步），按随机行走模式移动，后半程返回起点。

## 许可证

MIT
