import SwiftUI
import StayCore

public struct PinnedCardView: View {
    @ObservedObject public var session: PinSession
    public let onUnpin: () -> Void

    public init(session: PinSession, onUnpin: @escaping () -> Void) {
        self.session = session
        self.onUnpin = onUnpin
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "window.badge.magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.target.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(session.target.bundleID ?? "Native Window")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onUnpin) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Unpin Window")
            }

            Divider()

            HStack {
                // Mode Toggle
                Button(action: {
                    var next = session.configuration
                    switch next.mode {
                    case .corner: next.mode = .inPlace
                    case .inPlace: next.mode = .corner(.bottomRight)
                    }
                    session.configuration = next
                    OverlayWindowManager.shared.updateConfiguration(next, for: session.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCorner ? "arrow.up.left.and.arrow.down.right" : "pip")
                            .font(.system(size: 10))
                        Text(isCorner ? "Corner PiP" : "1:1 In-Place")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                if isCorner {
                    // Corner Selector
                    Button(action: {
                        var next = session.configuration
                        if case .corner(let c) = next.mode {
                            next.mode = .corner(c.next)
                            session.configuration = next
                            OverlayWindowManager.shared.updateConfiguration(next, for: session.id)
                        }
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                            Text(cornerLabel)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Spacer()

                // Opacity Slider
                HStack(spacing: 4) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Slider(
                        value: Binding(
                            get: { session.configuration.opacity },
                            set: { val in
                                var next = session.configuration
                                next.opacity = val
                                session.configuration = next
                                OverlayWindowManager.shared.updateConfiguration(next, for: session.id)
                            }
                        ),
                        in: 0.20...1.0
                    )
                    .frame(width: 50)
                    .controlSize(.mini)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor)))
    }

    private var isCorner: Bool {
        if case .corner = session.configuration.mode { return true }
        return false
    }

    private var cornerLabel: String {
        guard case .corner(let corner) = session.configuration.mode else { return "" }
        switch corner {
        case .bottomRight: return "BR"
        case .bottomLeft:  return "BL"
        case .topLeft:     return "TL"
        case .topRight:    return "TR"
        }
    }
}
