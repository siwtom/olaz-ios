import SwiftUI
import UIKit

@main
struct OlazIOSApp: App {
    @State private var engine = ZaloEngine()
    @AppStorage("olaz.appearance") private var appearanceMode = 0
    @AppStorage("olaz.accent") private var accentHex = "#0068FF"
    @Environment(\.scenePhase) private var scenePhase
    @State private var sharedFileItem: SharedFileItem?

    private struct SharedFileItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some Scene {
        WindowGroup {
            IOSRootView(engine: engine)
                .tint(Color(hex: accentHex) ?? ZaloTheme.blue)
                .preferredColorScheme(preferredScheme)
                .task {
                    NativeNotifier.shared.attach(engine: engine)
                    engine.start()
                }
                .onChange(of: scenePhase) { _, newValue in
                    switch newValue {
                    case .active:
                        engine.handleSceneDidBecomeActive()
                    case .background:
                        MediaLoader.purgeMemoryCache()
                    default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .olazShareFileRequested)) { note in
                    if let url = note.object as? URL {
                        sharedFileItem = SharedFileItem(url: url)
                    }
                }
                .sheet(item: $sharedFileItem) { item in
                    ActivityShareSheet(items: [item.url])
                        .ignoresSafeArea()
                }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case 1: .light
        case 2: .dark
        default: nil
        }
    }
}

/// Branches on device idiom rather than `horizontalSizeClass`, since iPhone XS Max (414×896)
/// reports `.regular` width in landscape.
@MainActor
enum IOSDeviceLayout {
    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}
