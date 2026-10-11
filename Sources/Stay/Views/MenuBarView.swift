import SwiftUI
import StayCore

public struct MenuBarView: View {
    @ObservedObject var coordinator = PinCoordinator.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stay")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(coordinator.activeSessions.count) Pinned")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            if coordinator.activeSessions.isEmpty {
                Text("No windows pinned.\nPress ⌥⌘T to pin active window.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(coordinator.activeSessions.values)) { session in
                    PinnedCardView(session: session) {
                        Task { await coordinator.unpin(windowID: session.id) }
                    }
                }
            }

            Divider()

            HStack {
                Button("Pin Active (⌥⌘T)") {
                    Task { try? await coordinator.toggleActiveWindow() }
                }
                Spacer()
                Button("Unpin All") {
                    Task { await coordinator.unpinAll() }
                }
                .disabled(coordinator.activeSessions.isEmpty)
            }

            Divider()

            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
