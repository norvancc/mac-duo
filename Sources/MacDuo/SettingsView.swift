import SwiftUI
import MetalKit
import DuoCore

private let accent = Color(red: 0.69, green: 0.75, blue: 1)
private let muted = Color(red: 0.53, green: 0.57, blue: 0.66)

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                DuoMark().frame(width: 35, height: 35)
                Text("Mac Duo").font(.system(size: 20, weight: .semibold))
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                Text("LIGHT IN MOTION").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5).foregroundStyle(muted).padding(.leading, 8)
                Spacer()
                Circle().fill(model.angle == nil ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(model.angle.map { "\(Int($0))°" } ?? "未连接")
                    .font(.system(size: 13, weight: .medium, design: .monospaced)).monospacedDigit()
                Toggle("启用合盖效果", isOn: $model.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .help("启用或暂停真实合盖效果")
            }
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("合上屏幕，\n画面留在视线里。")
                            .font(.system(size: 31, weight: .semibold)).lineSpacing(4)
                        Text("桌面保持原样，暗角随屏幕开合柔和收拢。")
                            .font(.system(size: 12)).foregroundStyle(muted)
                    }
                    previewCard
                    HStack(spacing: 14) {
                        Button { model.playDemo() } label: {
                            Label(model.demoRunning ? "正在试播…" : "全屏试播", systemImage: "play.fill")
                                .font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(Color.black)
                        .disabled(model.active)
                        Text("5 秒体验 · 无需合盖")
                            .font(.system(size: 11)).foregroundStyle(muted)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                controls.frame(width: 265)
            }
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            HStack(alignment: .center) {
                Circle().fill(model.ready ? accent : Color.orange).frame(width: 6, height: 6)
                Text(model.status).font(.system(size: 11)).foregroundStyle(muted).lineLimit(2)
                Spacer(minLength: 12)
                if !model.permission {
                    Button(model.checkingPermission ? "检查中…" : (model.permissionRequested ? "重新检查权限" : "授权屏幕录制")) { model.requestPermission() }
                        .font(.system(size: 11, weight: .medium)).buttonStyle(.bordered)
                        .disabled(model.checkingPermission)
                    Button("权限设置") { model.openPrivacySettings() }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                    Button("重启") { model.restartApplication() }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                } else if model.error != nil {
                    Button("重试") { model.clearError() }.font(.system(size: 11))
                }
                Text("⌃⌥⌘D  随时退出效果")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted.opacity(0.8))
            }
        }
        .padding(.horizontal, 32).padding(.top, 30).padding(.bottom, 24)
        .frame(width: 960)
        .background(Color(red: 0.055, green: 0.064, blue: 0.083))
        .preferredColorScheme(.dark)
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("效果预览").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(model.displayAngle))°").font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
            }.padding(.horizontal, 16).padding(.vertical, 13)
            ZStack {
                FoldPreview(angle: model.displayAngle, settings: model.settings)
                if model.wireframe {
                    MaskGrid(angle: model.displayAngle, settings: model.settings)
                }
            }
            .aspectRatio(1440.0 / 936, contentMode: .fit)
            .background(.black)
            .overlay(Rectangle().strokeBorder(.white.opacity(0.10), lineWidth: 1))
            VStack(spacing: 12) {
                HStack {
                    Text("合上").foregroundStyle(muted)
                    Slider(value: $model.previewAngle, in: 12...model.settings.startAngle)
                        .tint(accent).disabled(model.followSensor)
                        .accessibilityLabel("预览开合角度")
                    Text("展开").foregroundStyle(muted)
                }.font(.system(size: 10))
                HStack {
                    Toggle("跟随真实角度", isOn: $model.followSensor)
                    Spacer()
                    Toggle("遮罩网格", isOn: $model.wireframe)
                }.font(.system(size: 10)).toggleStyle(.checkbox).tint(accent)
            }.padding(16)
        }
        .background(.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("调到刚刚好").font(.system(size: 16, weight: .semibold))
                Text("为你的坐姿，找到舒服的视角。")
                    .font(.system(size: 11)).foregroundStyle(muted)
            }
            control("开始角度", value: $model.settings.startAngle, range: 70...125,
                    readout: "\(Int(model.settings.startAngle))°", footnote: "低于这个角度时，开始接住桌面。")
            control("暗角收拢", value: $model.settings.perspective, range: 0...1,
                    readout: "\(Int(model.settings.perspective * 100))%", footnote: "只改变遮罩轮廓，桌面位置和比例保持不变。")
            control("轮廓舒展", value: $model.settings.viewingDistance, range: 1.2...5,
                    readout: String(format: "%.1f ×", model.settings.viewingDistance), footnote: "数值越大，两侧暗角向内收拢得越缓。")
            control("柔化程度", value: $model.settings.maxBlur, range: 0...70,
                    readout: "\(Int(model.settings.maxBlur))", footnote: "上缘先柔化，靠近转轴处更清晰。")
            VStack(alignment: .leading, spacing: 8) {
                Label("只在内置屏幕上呈现", systemImage: "laptopcomputer")
                Label("截图仅在内存中短暂保留", systemImage: "lock.shield")
            }
            .font(.system(size: 10)).foregroundStyle(muted).padding(.top, 4)
            Button("恢复默认设置") { model.restoreDefaults() }
                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
        }
        .padding(22)
        .background(.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                         readout: String, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(readout).font(.system(size: 11, design: .monospaced)).foregroundStyle(accent).monospacedDigit()
            }
            Slider(value: value, in: range).tint(accent).accessibilityLabel(title)
            Text(footnote).font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DuoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.13))
            Path { path in
                path.move(to: .init(x: 8, y: 11)); path.addLine(to: .init(x: 27, y: 11))
                path.addLine(to: .init(x: 24, y: 23)); path.addLine(to: .init(x: 11, y: 23)); path.closeSubpath()
            }.stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            Path { path in
                path.move(to: .init(x: 8, y: 27)); path.addLine(to: .init(x: 27, y: 27))
            }.stroke(accent.opacity(0.5), lineWidth: 1.5)
        }
    }
}

private struct FoldPreview: NSViewRepresentable {
    let angle: Double
    let settings: FoldSettings
    final class Coordinator {
        let renderer = FoldRenderer()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        if let renderer = context.coordinator.renderer {
            renderer.configure(view)
            renderer.snapshot = CIImage(cgImage: SampleDesktop.image)
        }
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.angle = angle
        context.coordinator.renderer?.settings = settings
        DispatchQueue.main.async { view.draw() }
    }
}

private struct MaskGrid: View {
    let angle: Double
    let settings: FoldSettings
    var body: some View {
        Canvas { context, size in
            let frame = FoldGeometry.frame(angle: angle, settings: settings)
            func pixel(_ point: FoldPoint) -> CGPoint {
                return .init(x: point.x * size.width, y: (1 - point.y) * size.height)
            }
            for i in 0...6 {
                let fraction = Double(i) / 6
                var path = Path()
                path.move(to: pixel(.init(fraction, 0))); path.addLine(to: pixel(.init(fraction, 1)))
                path.move(to: pixel(.init(0, fraction))); path.addLine(to: pixel(.init(1, fraction)))
                context.stroke(path, with: .color(.cyan.opacity(0.3)), lineWidth: 0.7)
            }
            var outline = Path()
            outline.move(to: pixel(frame.quad.bottomLeft))
            for point in [frame.quad.bottomRight, frame.quad.topRight, frame.quad.topLeft] {
                outline.addLine(to: pixel(point))
            }
            outline.closeSubpath()
            context.stroke(outline, with: .color(.cyan.opacity(0.8)), lineWidth: 1)
        }.allowsHitTesting(false)
    }
}
