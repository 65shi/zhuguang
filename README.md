# 逐光 · Zhuguang

**让屏幕，再亮一点。** 一个轻量、原生的 macOS 菜单栏工具，利用 MacBook Pro 内置 XDR 屏幕的 EDR 余量，为日常桌面内容提供可调的额外亮度。

[下载最新版本](https://github.com/65shi/zhuguang/releases/latest) · [免责声明](DISCLAIMER.md) · [安全说明](SECURITY.md) · [参与贡献](CONTRIBUTING.md)

## 功能

- 菜单栏一键开启与关闭，启动时默认关闭增强。
- 1.00–2.00× 请求增益、三个快捷预设，并根据实时 EDR 余量限制实际增益。
- 定时关闭、低电量模式暂停、高温暂停、休眠和用户会话切换处理。
- 点击“恢复标准”或退出，即可移除增强图层；GUI 与自检使用独占进程锁，避免重复叠加。
- App Sandbox 与 Hardened Runtime；无联网、遥测、录屏或输入捕获代码，无第三方运行依赖。

## 兼容范围

| 项目 | 要求与说明 |
| --- | --- |
| 系统 | macOS 13 或更新版本 |
| 安装包 | Apple Silicon（arm64） |
| 屏幕 | 具有 EDR 能力的内置显示屏；主要面向 2021 年起的 14/16 英寸 MacBook Pro Liquid Retina XDR |
| 外接显示器 | 本版本不增强外接显示器 |
| 已记录实机 | M2 Pro / Mac14,9、macOS 26.1、内置 Liquid Retina XDR |

程序按屏幕报告的能力检测兼容性，不按芯片名称直接放行。其他机型和系统组合尚未全面验证。

## 安装与使用

1. 在 [Releases](https://github.com/65shi/zhuguang/releases/latest) 下载 `Zhuguang.dmg` 或 `Zhuguang.zip`。
2. 打开 DMG，将 **逐光.app** 拖到“应用程序”。
3. 启动后点击菜单栏的太阳图标，选择“开启 XDR 增强”。建议从较低强度开始，并配合系统亮度键调节基础亮度。
4. 使用结束后点击“恢复标准”或退出。关闭控制窗口后，菜单栏工具仍会运行。

登录启动仅启动工具，仍需手动开启增强。逐光不需要管理员、辅助功能或屏幕录制权限。

**当前发布包使用本地 ad-hoc 签名，尚无 Developer ID 身份背书或 Apple 公证。** macOS 可能拦截从互联网下载的安装包。请先核对下载来源与校验值；也可以审阅源码后自行构建。不要为了运行本工具而关闭 Gatekeeper、SIP 或其他系统保护。

## 工作原理

一个小尺寸 HDR 图层请求 macOS 分配 EDR 余量；另一个鼠标穿透的全屏 Metal 图层使用 multiply 合成，将桌面内容映射到额外亮度空间。均匀图层使用 4×4 浮点纹理、每秒 5 帧，显示缓冲区在后台队列取得。

增强图层属于当前进程，退出后消失。程序不直接写入系统 gamma 表，不修改硬件背光、显示预设或温控参数，也不尝试绕过 macOS 的亮度限制。

界面倍数是提交给显示合成器的增益，**不是亮度计读数，也不保证固定尼特或物理亮度翻倍**。Apple 的 1600 尼特规格指 HDR 峰值，不能解释为任意内容的全屏持续亮度保证。[Apple 技术规格](https://www.apple.com/macbook-pro/specs/)

## 使用前请了解

高亮度会增加耗电与发热，可能缩短单次电池续航；HDR 高光可能裁切，颜色观感也可能变化。调色、修图、观看 HDR 视频时建议关闭增强。全屏视频或受保护内容可能使增强暂时失效；请避免与其他增亮软件同时开启。

**本项目不提供“绝不会损坏电脑”的保证。** 已记录的单机短时测试显示渲染和关闭恢复正常；未进行硬件诊断，因此不能判断是否存在潜在损伤，也不能证明长期安全、屏幕寿命或所有机型兼容性。出现异常发热、闪烁、颜色异常或持续显示问题时，请立即关闭增强并退出。使用前请阅读完整的 [免责声明](DISCLAIMER.md)。

## 从源码构建

需要 macOS 与 Apple Xcode Command Line Tools（Swift 5.9 或更新版本）。在项目目录执行：

```bash
bash scripts/test.sh
bash scripts/build-app.sh --dmg
open dist/逐光.app
```

构建输出：

```text
dist/逐光.app   # 本地签名 App
dist/Zhuguang.zip   # 可分发压缩包
dist/Zhuguang.dmg   # 拖拽安装映像（使用 --dmg 时生成）
dist/SHA256SUMS.txt # 安装包 SHA-256 校验值
```

不需要 API 密钥、联网服务或第三方 Swift 包。CI 只运行策略检查、编译和打包，不在共享运行器上自动开启亮度增强。

## 诊断与验证

```bash
# 只查看屏幕能力，不更改亮度
dist/逐光.app/Contents/MacOS/Zhuguang --diagnose

# 先退出逐光；短时开启 1.10× 自检，随后自动关闭
dist/逐光.app/Contents/MacOS/Zhuguang --self-test
```

初始实现与安全加固版本的本机记录（2026-10-25）：

- 17 项增益限值、异常数值和暂停策略检查通过，debug/release 编译通过。
- 短时自检完成 19 个增益大于 1 的渲染帧；关闭后可见增强窗口为 0，开启前后 gamma 表最大差异为 0。
- 原生界面开启、调节、恢复与退出通过；重复自检被拦截，强制终止后可重新运行。
- 尚未用亮度计测量实际尼特。长期运行、屏幕寿命、全部系统版本、睡眠唤醒、Spaces/全屏视频及登录项等仍需扩大实机验证。

策略检查使用实际应用的 `BoostPolicy.swift`，可在没有 XCTest 的 Command Line Tools 环境运行。API 渲染成功和截图都不能单独证明物理亮度变化。

逐光 1.0.2 更名版已在同一台实机重新通过 17 项策略检查、debug/release 编译和 1.10× 短时自检：19 个增强帧，关闭后可见增强窗口 0，gamma 表差异 0。

## 项目结构

```text
Sources/       原生 Swift 应用与亮度策略
Resources/     App 元数据与沙盒权限
Tests/         策略检查
scripts/       测试、图标与发布包构建
.github/       CI 和问题反馈模板
```

## 参考与许可

- [Apple：EDR 图层开关](https://developer.apple.com/documentation/quartzcore/cametallayer/wantsextendeddynamicrangecontent)
- [Apple：当前 EDR 余量](https://developer.apple.com/documentation/appkit/nsscreen/maximumextendeddynamicrangecolorcomponentvalue)与[潜在 EDR 能力](https://developer.apple.com/documentation/appkit/nsscreen/maximumpotentialextendeddynamicrangecolorcomponentvalue)
- [Apple：XDR 亮度受限说明](https://support.apple.com/101865)
- [MaxNits](https://github.com/yogeshvar/maxnits)：HDR 激活与 multiply 图层思路的 MIT 许可参考，完整归属及许可见 [ThirdPartyNotices.md](ThirdPartyNotices.md)。
- [BrightIntosh](https://github.com/niklasr22/BrightIntosh)：现有方案的研究参考，未包含其 GPL 源码。

逐光原创代码按 [MIT License](LICENSE) 提供。重新分发时请保留 `LICENSE` 与 `ThirdPartyNotices.md`。本项目与 Apple 无隶属或背书关系。
