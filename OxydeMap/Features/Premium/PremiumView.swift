import SwiftUI
import StoreKit
import OxydeCore

/// Oxyde Premium. Prices come from the App Store; nothing is shown as purchasable when
/// products aren't configured. Navigation and safety features are always free.
struct PremiumView: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        let store = model.premium
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    OxydeMark(size: 54)
                    Text("Oxyde Premium").font(.title.bold())
                    Text("Premium themes (Executive, Luxury, Cyber, Synthwave) and future premium styles.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            Section("Always free") {
                Label("Turn-by-turn navigation, voice guidance and rerouting", systemImage: "checkmark")
                Label("Traffic, incidents and driver reports", systemImage: "checkmark")
                Label("CarPlay", systemImage: "checkmark")
                Label("11 themes and the theme editor", systemImage: "checkmark")
            }
            Section {
                if store.isUnlocked {
                    Label("Premium is active", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else if !store.isConfigured {
                    Text("Purchases aren't set up in this build. Add product IDs to the configuration (docs/APP_STORE.md).")
                        .foregroundStyle(.secondary)
                } else if store.isLoading {
                    ProgressView()
                } else if let e = store.loadError {
                    Text(e).foregroundStyle(.orange)
                    Button("Try Again") { Task { await store.loadProducts() } }
                } else {
                    ForEach(store.products, id: \.id) { p in
                        Button {
                            buy(p)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(p.displayName).foregroundStyle(.primary)
                                    Text(p.description).font(.caption).foregroundStyle(.secondary)
                                    if let sub = p.subscription {
                                        Text("Renews every \(period(sub.subscriptionPeriod)) until cancelled.").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(p.displayPrice).bold()
                            }
                        }
                        .disabled(busy)
                    }
                }
                Button("Restore Purchases") {
                    Task {
                        busy = true
                        message = await store.restore()
                        busy = false
                    }
                }
                .disabled(busy || !store.isConfigured)
            } footer: {
                Text("Subscriptions are billed to your Apple ID and can be managed or cancelled in iPhone Settings > Apple ID > Subscriptions.")
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("Premium")
    }

    private func buy(_ p: Product) {
        Task {
            busy = true
            switch await model.premium.purchase(p) {
            case .purchased: message = "Thank you! Premium is unlocked."
            case .pending: message = "Your purchase is waiting for approval."
            case .cancelled: message = nil
            case .failed(let e): message = e
            }
            busy = false
        }
    }

    private func period(_ p: Product.SubscriptionPeriod) -> String {
        switch p.unit {
        case .day: return p.value == 1 ? "day" : "\(p.value) days"
        case .week: return p.value == 1 ? "week" : "\(p.value) weeks"
        case .month: return p.value == 1 ? "month" : "\(p.value) months"
        case .year: return p.value == 1 ? "year" : "\(p.value) years"
        @unknown default: return "period"
        }
    }
}
