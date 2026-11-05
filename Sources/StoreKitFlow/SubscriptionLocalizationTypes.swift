/// Original subscription title categories retained for SubscriptionLocale compatibility.
public enum SubscriptionPeriodType: String, Sendable {
    case week, month, year, lifetime
}

/// Original button categories retained for SubscriptionLocale compatibility.
public enum SubscriptionButtonType: String, Sendable {
    case standard, freeTrial, payUpFront, payAsYouGo, lifetime
}
