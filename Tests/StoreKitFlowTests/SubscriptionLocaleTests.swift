import Testing
import StoreKitFlow

@Test func legacyTitlesAndButtonsRemainAvailable() {
    #expect(SubscriptionLocale.subscriptionTitle(periodType: .month, languageCode: "zh_Hans") == "每月会员")
    #expect(SubscriptionLocale.subscriptionButtonText(type: .freeTrial, languageCode: "zh_Hans") == "开始免费试用")
    #expect(SubscriptionLocale.subscriptionButtonText(type: .standard, languageCode: "en") == "Subscribe")
    #expect(SubscriptionLocale.subscriptionTitle(periodType: .year, languageCode: "en", isShort: true) == "Yearly")
    #expect(SubscriptionLocale.subscriptionButtonText(type: .standard, languageCode: "unsupported") == "Subscribe")
}

@Test func legacyUnknownPeriodDefaultsToDay() {
    #expect(SubscriptionLocale.getUnit(from: nil) == "day")
}

@Test func legacyLanguagesHaveButtonAndTitle() {
    let languages = ["ar", "de", "en", "es", "fil", "fr", "id", "it", "ja", "ko", "pl", "pt", "ru", "th", "tr", "uk", "vi", "zh_Hans", "zh_Hant"]
    for language in languages {
        #expect(!SubscriptionLocale.subscriptionTitle(periodType: .month, languageCode: language).isEmpty)
        #expect(!SubscriptionLocale.subscriptionButtonText(type: .standard, languageCode: language).isEmpty)
        if language != "en" {
            #expect(SubscriptionLocale.subscriptionTitle(periodType: .month, languageCode: language) != SubscriptionLocale.subscriptionTitle(periodType: .month, languageCode: "en"))
            #expect(SubscriptionLocale.subscriptionButtonText(type: .standard, languageCode: language) != SubscriptionLocale.subscriptionButtonText(type: .standard, languageCode: "en"))
        }
    }
}
