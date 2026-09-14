# Mac Duo

让 MacBook 合盖时的桌面，像 Lomo 照片一样柔和消隐。

[项目网页与交互预览](https://norvancc.github.io/mac-duo/) · [下载](https://github.com/norvancc/mac-duo/releases/latest) · [English](README.md) · [MIT 许可证](LICENSE)

原生 macOS 菜单栏 App。合盖时只截取一帧内置屏幕画面，**截图的位置和比例保持不变**，通过随铰链角度收拢的梯形柔边遮罩，配合由上至下的渐变高斯模糊，逐渐淡入黑色。文字、窗口和图标都不会被拉伸。

![使用生成的示例桌面展示暗角和渐变模糊](docs/preview.png)

*预览使用程序生成的示例桌面，不包含真实屏幕截图。*

## 功能

- 读取兼容 MacBook 的真实合盖角度，随开合方向实时变化。
- 只改变遮罩形状，底部两角始终固定在屏幕转轴的两端。
- 柔边暗角向黑色自然过渡，屏幕四周提前渐隐，避免硬裁切。
- 提供五秒全屏试播、窗口内示例预览和遮罩网格。
- 可调整开始角度、暗角收拢、轮廓舒展和柔化程度。
- 每次过渡只截一帧，保存在内存中，结束后释放；不采集音频，无统计和网络请求。
- 开盖、休眠、切换显示器或传感器不可用时移除覆盖层。

## 下载与安装

[下载 Mac Duo 1.0.6（DMG）](https://github.com/norvancc/mac-duo/releases/download/v1.0.6/Mac-Duo-1.0.6-universal.dmg)，打开后将 **Mac Duo** 拖入「应用程序」。

发布包为 Apple Silicon / Intel 通用版本，使用 Developer ID 签名，并已通过 Apple 公证。需要 macOS 14+；支持两种处理器架构不代表所有机型都具备兼容的角度传感器。[发行页面](https://github.com/norvancc/mac-duo/releases/tag/v1.0.6) 另提供 ZIP 和 SHA-256 校验文件。

## 从源码构建

需要 macOS 14+、支持 Metal 的 Mac，以及包含 macOS SDK 的 Xcode 和 Swift 5.9+。自动合盖效果需要设备暴露兼容的铰链 HID 传感器，已在 Mac16,8 / macOS 15.7.9 验证；不同机型的支持情况可能不同。

打包 App 需要本机的 **Apple Development** 签名身份。仓库不包含证书或私钥。

```sh
git clone https://github.com/norvancc/mac-duo.git
cd mac-duo
bash scripts/build-app.sh
open 'build/Mac Duo.app'
```

脚本自动选择可用的开发签名身份，也可显式指定：

```sh
MAC_DUO_SIGNING_IDENTITY='Apple Development: Your Name (TEAMID)' bash scripts/build-app.sh
```

更新时保持签名身份和 App 路径一致，等待打包和签名验证完成后再打开 App，以便系统识别已有录屏授权。此脚本生成本地开发构建，不执行公证；GitHub 发布包已签名并公证。

没有签名身份也可编译、运行测试和离屏渲染检查：

```sh
swift build -c release
swift test
.build/release/MacDuo --render-check
```

## 使用

1. 打开 App，在系统「隐私与安全性」的录屏权限页面允许 Mac Duo。
2. 保持「启用合盖效果」开启。默认先将屏幕打开到 **112° 以上**，再合到 **110° 以下**开始效果。
3. 点击「全屏试播」体验约五秒，无需移动屏幕，也不要求铰链传感器。
4. **Control + Option + Command + D** 停止效果；设置窗口激活时也可按 Escape。

窗口内示例预览不需要录屏权限。全屏截图需要录屏权限和正在使用的内置显示屏。关闭设置窗口后 App 继续驻留菜单栏，没有登录启动项。

若系统显示已授权但截图失败，点击「重新检查权限」，必要时点击「重启」。从临时签名切换到不同签名身份时，可能需要刷新一次系统中的权限记录。

## 实现与边界

IOKit 在独立队列读取铰链传感器；向下穿过阈值时由 ScreenCaptureKit 截图。Core Image 对固定原图施加渐变模糊，`CIPerspectiveTransform` 只用于生成梯形遮罩，最终通过 Metal 呈现在不透明、鼠标穿透的覆盖层中。

截图是静态画面，下方的 App 会继续运行。受 DRM 保护的内容可能无法捕获。屏幕停在半合状态 12 秒未继续移动，会自动退出效果。App 遵循系统原有的睡眠行为；唤醒后直接显示正常桌面，下一次合盖重新截图。

铰链接口不是 Apple 承诺稳定的公开角度 API。这是独立的视觉实验项目，不隶属于 Apple；不进行图片透视校正或头部追踪。

## 验证

```sh
swift test
swift run -c release MacDuo --render-check
swift run -c release MacDuo --render-check --benchmark
```

测试覆盖遮罩几何、底边固定、数值稳定性和触发状态机。渲染检查逐像素比较六种遮罩状态，确认原图坐标与比例不变，并检查柔边扩散、黑色背景和屏幕四周渐隐。生成的图片位于 `build/render-check/`。

更多实现说明、资料链接见 [English README](README.md)，参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 发布包与网页

使用自己的 Developer ID Application 签名身份和 `notarytool` 钥匙串配置生成已公证的通用 DMG / ZIP：

```sh
MAC_DUO_NOTARY_PROFILE='your-notary-profile' bash scripts/build-release.sh
```

可通过 `MAC_DUO_RELEASE_SIGNING_IDENTITY` 指定证书名称或 SHA-1。产物及校验文件写入 `build/distribution/<版本>/`，不会覆盖本地开发 App。

静态网页位于 `docs/`，由 GitHub Pages 托管。运行 `python3 -m http.server 8765 --directory docs` 后打开 `http://localhost:8765` 即可预览。网页动效使用七帧程序生成的示例桌面插值，不读取浏览器的屏幕或传感器。

## 许可证

[MIT](LICENSE) © 2026 norvancc。
