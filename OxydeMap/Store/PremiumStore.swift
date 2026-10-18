import StoreKit
import Observation

/// Oxyde Premium through StoreKit 2. Premium covers extra themes and advanced styling
/// only. Navigation, guidance, rerouting, traffic, reports and CarPlay are never gated.
@MainActor
@Observable
final class PremiumStore {
    private(set) var products: [Product] = []
    private(set) var purchasedIDs: Set<String> = []
    private(set) var loadError: String?
    private(set) var isLoading = false
    /// Debug builds can unlock premium from Diagnostics to test gated themes without a
    /// sandbox account. Not available in release builds.
    var developerUnlock = false

    @ObservationIgnored let productIDs: [String]
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(productIDs: [String]) { self.productIDs = productIDs }

    var isConfigured: Bool { !productIDs.isEmpty }

    var isUnlocked: Bool {
        #if DEBUG
        if developerUnlock { return true }
        #endif
        return !purchasedIDs.isEmpty
    }

    func start() async {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await t.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: productIDs).sorted { $0.price < $1.price }
            loadError = products.isEmpty ? "No products were returned by the App Store." : nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { ids.insert(t.productID) }
        }
        purchasedIDs = ids
    }

    enum PurchaseOutcome { case purchased, pending, cancelled, failed(String) }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let t) = verification else { return .failed("The purchase could not be verified.") }
                await t.finish()
                await refreshEntitlements()
                return .purchased
            case .pending: return .pending
            case .userCancelled: return .cancelled
            @unknown default: return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async -> String? {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return purchasedIDs.isEmpty ? "No previous purchases were found for this Apple ID." : nil
        } catch {
            return error.localizedDescription
        }
    }
}
