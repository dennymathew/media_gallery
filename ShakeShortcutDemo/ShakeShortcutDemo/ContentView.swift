import SwiftUI
import UIKit

// MARK: - Real shake detection

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - Debug keyboard shortcut

#if DEBUG
enum DebugShakeShortcut {
    // Avoid Command+Shift+Z: it's the system Redo shortcut.
    static let key: KeyEquivalent = "z"
    static let modifiers: EventModifiers = [.control, .command]
}

struct DebugShakeModifier: ViewModifier {
    let perform: () -> Void

    func body(content: Content) -> some View {
        content.background(
            // Not .hidden(): hidden views may not register keyboard shortcuts.
            Button("Debug Shake", action: perform)
                .keyboardShortcut(DebugShakeShortcut.key, modifiers: DebugShakeShortcut.modifiers)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}

extension View {
    func onDebugShake(perform: @escaping () -> Void) -> some View {
        modifier(DebugShakeModifier(perform: perform))
    }
}
#endif

// MARK: - UI

struct ContentView: View {
    @State private var shakeCount = 0
    @State private var lastSource = "none"

    var body: some View {
        VStack(spacing: 16) {
            Text("Shakes: \(shakeCount)")
                .font(.largeTitle.monospacedDigit())
            Text("Last source: \(lastSource)")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            handleShake(source: "device")
        }
        #if DEBUG
        .onDebugShake { handleShake(source: "keyboard") }
        #endif
    }

    private func handleShake(source: String) {
        shakeCount += 1
        lastSource = source
        print("Shake handled via \(source)")
    }
}

#Preview {
    ContentView()
}
