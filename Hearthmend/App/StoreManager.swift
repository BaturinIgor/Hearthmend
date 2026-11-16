import Foundation
import StoreKit
import HearthCore

/// Покупки через StoreKit 2. Награду выдает ядро (Game.grantPurchase), оно же не дает выдать
/// одну транзакцию дважды. Транзакция закрывается (finish) только после выдачи и сохранения.
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var purchasing: String?
    @Published var lastError: String?

    private weak var store: GameStore?
    private var updates: Task<Void, Never>?

    init() {}

    func attach(_ store: GameStore) {
        self.store = store
        updates?.cancel()
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await loadProducts()
            await syncEntitlements()
        }
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: Products.all)
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            lastError = error.localizedDescription
        }
    }

    func price(_ id: String) -> String? { products[id]?.displayPrice }

    func buy(_ id: String) async {
        guard let product = products[id], purchasing == nil else { return }
        purchasing = id
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Восстановление покупок: подтягивает транзакции с серверов Apple.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await syncEntitlements()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.revocationDate == nil {
            store?.grantPurchase(productId: transaction.productID,
                                 transactionId: String(transaction.id),
                                 expires: transaction.expirationDate)
        }
        await transaction.finish()
    }

    /// Текущие права: подписка VIP и разовые покупки (стартовый набор).
    private func syncEntitlements() async {
        var vipUntil: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == Products.vipMonthly {
                vipUntil = max(vipUntil ?? .distantPast, t.expirationDate ?? .distantFuture)
            } else {
                store?.grantPurchase(productId: t.productID, transactionId: String(t.id), expires: nil)
            }
        }
        store?.updateVIP(expires: vipUntil)
    }
}
