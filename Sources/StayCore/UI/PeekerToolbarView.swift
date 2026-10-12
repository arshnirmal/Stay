import SwiftUI

public struct PeekerToolbarView: View {
    @Binding public var configuration: PeekerConfiguration
    public let onToggleMode: () -> Void
    public let onCycleCorner: () -> Void
    public let onUnpin: () -> Void

    public init(
        configuration: Binding<PeekerConfiguration>,
        onToggleMode: @escaping () -> Void,
        onCycleCorner: @escaping () -> Void,
        onUnpin: @escaping () -> Void
    ) {
        self._configuration = configuration
        self.onToggleMode = onToggleMode
        self.onCycleCorner = onCycleCorner
        self.onUnpin = onUnpin
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleMode) {
                Image(systemName: isCornerMode ? "arrow.up.left.and.arrow.down.right" : "pip")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .help(isCornerMode ? "Switch to 1:1 In-Place HUD (⌥⇧T)" : "Switch to Corner Thumbnail (⌥⇧T)")

            if isCornerMode {
                Button(action: onCycleCorner) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                        Text(cornerLabel)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
                .buttonStyle(.plain)
                .help("Cycle Screen Corner (⌥⇧C)")
            }

            Divider()
                .frame(height: 12)

            Slider(value: $configuration.opacity, in: 0.20...1.0)
                .frame(width: 60)
                .controlSize(.mini)
                .help("Adjust Transparency (\(Int(configuration.opacity * 100))%)")

            Divider()
                .frame(height: 12)

            Button(action: onUnpin) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Unpin Window")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }

    private var isCornerMode: Bool {
        if case .corner = configuration.mode { return true }
        return false
    }

    private var cornerLabel: String {
        guard case .corner(let corner) = configuration.mode else { return "" }
        switch corner {
        case .bottomRight: return "BR"
        case .bottomLeft:  return "BL"
        case .topLeft:     return "TL"
        case .topRight:    return "TR"
        }
    }
}
