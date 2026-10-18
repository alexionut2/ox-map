import SwiftUI
import SwiftData
import OxydeCore

@main
struct OxydeMapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .environment(model.themes)
                .environment(model.location)
                .environment(model.navigation)
                .modelContainer(model.persistence.container)
                .onOpenURL { model.handle(url: $0) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // CarPlay may launch the app with no phone UI, so services are created here
        // rather than lazily by the first SwiftUI view.
        _ = AppModel.shared
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var showSplash = !ProcessInfo.processInfo.arguments.contains("-uiTestingReset")

    var body: some View {
        ZStack {
            Group {
                if settings.value.hasCompletedOnboarding {
                    MainMapView()
                } else {
                    OnboardingView()
                }
            }
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.45)) { showSplash = false } }
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(1)
            }
        }
        .tint(model.accentColor)
        .preferredColorScheme(model.preferredColorScheme)
        .animation(.easeInOut(duration: 0.35), value: settings.value.hasCompletedOnboarding)
        .alert(item: Binding(get: { model.pendingImport }, set: { model.pendingImport = $0 })) { pending in
            Alert(title: Text("Add “\(pending.theme.name)”?"),
                  message: Text("This theme was shared with you. It will be added to My Themes."),
                  primaryButton: .default(Text("Add Theme")) { model.themes.save(pending.theme) },
                  secondaryButton: .cancel())
        }
    }
}
