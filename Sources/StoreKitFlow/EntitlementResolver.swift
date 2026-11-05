import Foundation

public enum EntitlementResolver {
    public static func resolve(_ evidence: EntitlementEvidence, configuration: StoreConfiguration,
                               now: Date, previous: EntitlementSnapshot = .init()) -> EntitlementSnapshot {
        let definitions = Dictionary(uniqueKeysWithValues: configuration.products.map { ($0.id, $0) })
        var latest: [String: TransactionDetails] = [:]
        for t in evidence.history + evidence.current + evidence.subscriptions.filter(\.verified).map(\.transaction) {
            if let old = latest[t.key], old.signedDate > t.signedDate { continue }
            if let old = latest[t.key], old.signedDate == t.signedDate, old.revocationDate != nil, t.revocationDate == nil { continue }
            latest[t.key] = t
        }
        var grants: [String: EntitlementGrant] = [:]
        var excluded = evidence.rejectedKeys
        var uncertain = !evidence.complete
        func accepted(_ t: TransactionDetails) -> Bool {
            !evidence.rejectedKeys.contains(t.key) && t.revocationDate == nil && !t.isUpgraded &&
            (t.ownership == .purchased || (t.ownership == .familyShared && configuration.acceptsFamilySharing))
        }
        func add(_ t: TransactionDetails, until: Date?, reason: String) {
            guard accepted(t), let definition = definitions[t.productID], definition.kind == t.kind else { return }
            for right in definition.entitlements {
                let grant = EntitlementGrant(entitlementID: right, productID: t.productID, transactionKey: t.key,
                                             validUntil: until, ownership: t.ownership, reason: reason)
                grants[grant.id] = grant
            }
        }
        for t in latest.values where !accepted(t) { excluded.insert(t.key) }
        for value in evidence.current {
            let t = latest[value.key] ?? value
            guard accepted(t) else { continue }
            switch t.kind {
            case .nonConsumable: add(t, until: nil, reason: "permanent")
            case .autoRenewable:
                let statuses = evidence.subscriptions.filter { $0.verified && $0.transaction.key == t.key }
                if let status = statuses.max(by: { $0.transaction.signedDate < $1.transaction.signedDate }) {
                    switch status.state {
                    case .subscribed:
                        if let expiry = t.expirationDate, expiry > now { add(t, until: expiry, reason: "subscribed") }
                        else { excluded.insert(t.key) }
                    case .inGracePeriod:
                        if let end = status.gracePeriodExpirationDate, end > now { add(t, until: end, reason: "gracePeriod") }
                        else if status.gracePeriodExpirationDate == nil { uncertain = true }
                        else { excluded.insert(t.key) }
                    case .expired, .revoked, .inBillingRetryPeriod: excluded.insert(t.key)
                    case .unknown: uncertain = true
                    }
                } else if let expiry = t.expirationDate, expiry > now {
                    add(t, until: expiry, reason: "currentEntitlement")
                } else {
                    // An expired transaction may be a grace entitlement. Do not invent its grace deadline.
                    uncertain = true
                }
            case .nonRenewable, .consumable: break
            case .unsupported: uncertain = true
            }
        }
        // Subscription status can arrive before a currentEntitlements snapshot catches up.
        for status in evidence.subscriptions where status.verified {
            // A freshly signed transaction is not evidence of a newer renewal state.
            // Apply the verified group state while retaining the latest revocation/upgrade fields.
            let t = latest[status.transaction.key] ?? status.transaction
            guard accepted(t) else { continue }
            switch status.state {
            case .subscribed:
                if let end = t.expirationDate, end > now { add(t, until: end, reason: "subscribed") }
                else { excluded.insert(t.key) }
            case .inGracePeriod:
                if let end = status.gracePeriodExpirationDate, end > now { add(t, until: end, reason: "gracePeriod") }
                else if status.gracePeriodExpirationDate == nil { uncertain = true }
                else { excluded.insert(t.key) }
            case .expired, .revoked, .inBillingRetryPeriod: excluded.insert(t.key)
            case .unknown: uncertain = true
            }
        }
        for definition in configuration.products where definition.kind == .nonRenewable {
            guard let term = definition.term else { continue }
            let transactions = latest.values.filter { $0.productID == definition.id && $0.kind == .nonRenewable && accepted($0) }
                .sorted { $0.purchaseDate == $1.purchaseDate ? $0.id < $1.id : $0.purchaseDate < $1.purchaseDate }
            var accumulated: Date?
            for t in transactions {
                let start = definition.stacks ? max(t.purchaseDate, accumulated ?? t.purchaseDate) : t.purchaseDate
                guard let end = term.end(from: start) else { uncertain = true; continue }
                accumulated = end
                if end > now { add(t, until: end, reason: "nonRenewing") }
                else { excluded.insert(t.key) }
            }
        }
        if uncertain {
            for grant in previous.grants where grants[grant.id] == nil && !excluded.contains(grant.transactionKey) {
                guard grant.validUntil.map({ $0 > now }) ?? true else { continue }
                // Non-renewing grants are reconstructed from history, never retained across a revocation.
                if definitions[grant.productID]?.kind == .nonRenewable,
                   evidence.history.contains(where: { $0.productID == grant.productID && $0.revocationDate != nil }) { continue }
                grants[grant.id] = grant
            }
        }
        let all = grants.values.filter { !excluded.contains($0.transactionKey) }.sorted { $0.id < $1.id }
        let pro = all.filter { $0.entitlementID == "pro" }
        return EntitlementSnapshot(grants: all,
            pro: ProStatus(access: pro.isEmpty ? (uncertain ? .unknown : .inactive) : .active,
                           sources: pro, evaluatedAt: now, isStale: uncertain,
                           reason: pro.isEmpty ? (uncertain ? "需要重新核实" : "没有有效 Pro 权益") : "有效购买权益"),
            nextEvaluationAt: all.compactMap(\.validUntil).filter { $0 > now }.min())
    }
}
