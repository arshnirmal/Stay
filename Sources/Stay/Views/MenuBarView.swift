import SwiftUI
import StayCore

public struct MenuBarView: View {
    @ObservedObject var coordinator = PinCoordinator.shared
    @ObservedObject var permissions = PermissionService.shared

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

            // Permissions warning if not granted
            if !permissions.hasAccessibility || !permissions.hasScreenRecording {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Permissions Required")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                    }

                    if !permissions.hasAccessibility {
                        HStack {
                            Text("Accessibility:")
                                .font(.system(size: 10))
                            Spacer()
                            Button("Grant") {
                                permissions.promptForAccessibility()
                                permissions.openSystemSettingsAccessibility()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }

                    if !permissions.hasScreenRecording {
                        HStack {
                            Text("Screen Recording:")
                                .font(.system(size: 10))
                            Spacer()
                            Button("Grant") {
                                permissions.promptForScreenRecording()
                                permissions.openSystemSettingsScreenRecording()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
            }

            Divider()

            if coordinator.activeSessions.isEmpty {
                VStack(spacing: 4) {
                    Text("No reference windows pinned.")
                        .font(.system(size: 12, weight: .medium))
                    Text("⌥⇧P : Pin / Unpin Active\n⌥⇧T : Toggle 1:1 / Corner\n⌥⇧C : Cycle Corner")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
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
                Button("Pin Active (⌥⇧P)") {
                    Task {
                        do {
                            try await coordinator.toggleActiveWindow()
                        } catch {
                            NSLog("[Stay] Failed to pin: \(error)")
                            permissions.checkPermissions()
                        }
                    }
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
        .onAppear {
            permissions.checkPermissions()
        }
    }
}
