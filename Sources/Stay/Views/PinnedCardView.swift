import SwiftUI
import StayCore

public struct PinnedCardView: View {
    public let session: PinSession
    public let onUnpin: () -> Void

    public init(session: PinSession, onUnpin: @escaping () -> Void) {
        self.session = session
        self.onUnpin = onUnpin
    }

    public var body: some View {
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
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor)))
    }
}
