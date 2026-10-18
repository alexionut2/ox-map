import SwiftUI
import OxydeCore

/// First launch: brand, the customization pitch, then location permission at the moment
/// it is explained, then a starting profile. No permission is requested before the user
/// sees why.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(LocationManager.self) private var location
    @State private var page = 0

    var body: some View {
        ZStack {
            OX.black.ignoresSafeArea()
            TabView(selection: $page) {
                welcome.tag(0)
                customize.tag(1)
                permissions.tag(2)
                profiles.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.easeInOut, value: page)
        }
        .preferredColorScheme(.dark)
    }

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            OxydeMark(size: 120)
            OxydeWordmark(size: 30)
            Text("Your routes. Your map. Your driving experience.")
                .font(.title3.weight(.medium)).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") { page = 1 }.buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.start")
        }
        .padding(24)
    }

    private var customize: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Make it yours").font(.largeTitle.bold())
            Text("Fifteen map styles, from clean daily driving to deep-black night modes and neon. Build your own in Map Studio and take it into CarPlay.")
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ThemeRegistry.all.prefix(8)) { t in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 14).fill(Color(hex: t.palette.background))
                                .overlay(alignment: .bottomLeading) {
                                    Capsule().fill(Color(hex: t.route.color)).frame(width: 70, height: 6).padding(12)
                                        .shadow(color: Color(hex: t.route.glowColor).opacity(t.route.glow), radius: 6)
                                }
                                .frame(width: 120, height: 90)
                            Text(t.name).font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            Spacer()
            Button("Continue") { page = 2 }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "location.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Location for navigation").font(.largeTitle.bold())
            Text("Oxyde Map uses your location to show where you are, calculate routes and guide you turn by turn. While navigating, it keeps guiding when the screen is off; iOS shows a blue indicator whenever that happens.")
                .foregroundStyle(.secondary)
            Text("Routes and search go to Apple Maps. If traffic reports are set up, Oxyde's server receives the map area around your route and the position of any report you submit. It never receives your trip history.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            switch location.permission {
            case .notDetermined:
                Button("Allow Location") { location.requestWhenInUse() }.buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onboarding.allowLocation")
                Button("Not Now") { page = 3 }.buttonStyle(SecondaryButtonStyle())
            case .denied, .restricted:
                Text("Location is off. You can still browse the map and search, and turn location on in Settings anytime.")
                    .font(.callout)
                Button("Continue") { page = 3 }.buttonStyle(PrimaryButtonStyle())
            case .whenInUse, .always:
                Label("Location allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Continue") { page = 3 }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .onChange(of: location.permission) { _, p in if p != .notDetermined { page = 3 } }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a starting profile").font(.title.bold()).padding(.top, 40)
            Text("You can change everything later in Settings.").foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(DriverProfile.builtIns) { p in
                        Button {
                            settings.apply(p)
                            model.haptics.success(enabled: settings.value.hapticsEnabled)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: p.symbol).font(.title2).frame(width: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.headline)
                                    Text(p.summary).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.value.activeProfileID == p.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .oxPanel(.solid, cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.\(p.id)")
                    }
                }
            }
            Button("Start Driving") { settings.value.hasCompletedOnboarding = true }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.finish")
        }
        .padding(24)
    }
}
