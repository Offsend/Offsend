import DetectionCore
import Foundation
import MaskingCore
import StorageCore

enum AppLocalization {
    static func defaultNoRiskActionName(_ action: DefaultNoRiskAction) -> String {
        switch action {
        case .pasteOriginal:
            return OffsendStrings.settingsDefaultActionPasteOriginal
        case .copyOriginal:
            return OffsendStrings.settingsDefaultActionCopyOriginal
        case .showToast:
            return OffsendStrings.settingsDefaultActionShowToast
        }
    }

    static func restoreBehaviorName(_ behavior: RestoreBehavior) -> String {
        switch behavior {
        case .copyToClipboard:
            return OffsendStrings.settingsRestoreBehaviorCopyToClipboard
        case .pasteIntoActiveApp:
            return OffsendStrings.settingsRestoreBehaviorPasteIntoActiveApp
        }
    }

    static func mappingTTLName(_ ttl: MappingTTL) -> String {
        switch ttl {
        case .oneHour:
            return OffsendStrings.settingsMappingTTLOneHour
        case .sixHours:
            return OffsendStrings.settingsMappingTTLSixHours
        case .twentyFourHours:
            return OffsendStrings.settingsMappingTTLTwentyFourHours
        case .neverStore:
            return OffsendStrings.settingsMappingTTLNeverStore
        }
    }

    static func customDictionaryKindName(_ kind: CustomDictionaryKind) -> String {
        switch kind {
        case .client:
            return OffsendStrings.dictionaryKindClient
        case .company:
            return OffsendStrings.dictionaryKindCompany
        case .project:
            return OffsendStrings.dictionaryKindProject
        case .sensitiveTerm:
            return OffsendStrings.dictionaryKindSensitiveTerm
        case .internalDomain:
            return OffsendStrings.dictionaryKindInternalDomain
        }
    }

    static func riskLevelName(_ level: RiskLevel) -> String {
        switch level {
        case .low:
            return OffsendStrings.riskLevelLow
        case .medium:
            return OffsendStrings.riskLevelMedium
        case .high:
            return OffsendStrings.riskLevelHigh
        case .critical:
            return OffsendStrings.riskLevelCritical
        }
    }

    static func licensePlanName(_ plan: LicenseState.Plan) -> String {
        switch plan {
        case .free:
            return OffsendStrings.settingsPlanFree
        case .pro:
            return OffsendStrings.settingsPlanPro
        }
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func sensitiveEntityTypeName(_ type: SensitiveEntityType, plural: Bool = false) -> String {
        switch type {
        case .email:
            return plural ? OffsendStrings.entityEmailAddresses : OffsendStrings.entityEmailAddress
        case .phone:
            return plural ? OffsendStrings.entityPhoneNumbers : OffsendStrings.entityPhoneNumber
        case .money:
            return plural ? OffsendStrings.entityAmounts : OffsendStrings.entityAmount
        case .url:
            return plural ? OffsendStrings.entityUrls : OffsendStrings.entityUrl
        case .ipAddress:
            return plural ? OffsendStrings.entityIpAddresses : OffsendStrings.entityIpAddress
        case .internalDomain, .customInternalDomain:
            return plural ? OffsendStrings.entityInternalDomains : OffsendStrings.entityInternalDomain
        case .contractId:
            return plural ? OffsendStrings.entityContractIDs : OffsendStrings.entityContractID
        case .invoiceId:
            return plural ? OffsendStrings.entityInvoiceIDs : OffsendStrings.entityInvoiceID
        case .orderId:
            return plural ? OffsendStrings.entityOrderIDs : OffsendStrings.entityOrderID
        case .creditCardLike:
            return plural ? OffsendStrings.entityCreditCards : OffsendStrings.entityCreditCard
        case .iban:
            return plural ? OffsendStrings.entityIbans : OffsendStrings.entityIban
        case .customClient:
            return plural ? OffsendStrings.entityClientNames : OffsendStrings.entityClientName
        case .customCompany:
            return plural ? OffsendStrings.entityCompanyNames : OffsendStrings.entityCompanyName
        case .customProject:
            return plural ? OffsendStrings.entityProjectNames : OffsendStrings.entityProjectName
        case .customSensitiveTerm:
            return plural ? OffsendStrings.entitySensitiveTerms : OffsendStrings.entitySensitiveTerm
        case .apiKeyGeneric:
            return plural ? OffsendStrings.entityApiKeys : OffsendStrings.entityApiKey
        case .openAIAPIKey:
            return plural ? OffsendStrings.entityOpenAIAPIKeys : OffsendStrings.entityOpenAIAPIKey
        case .awsAccessKeyId:
            return plural ? OffsendStrings.entityAwsAccessKeys : OffsendStrings.entityAwsAccessKey
        case .githubToken:
            return plural ? OffsendStrings.entityGithubTokens : OffsendStrings.entityGithubToken
        case .slackToken:
            return plural ? OffsendStrings.entitySlackTokens : OffsendStrings.entitySlackToken
        case .stripeKey:
            return plural ? OffsendStrings.entityStripeKeys : OffsendStrings.entityStripeKey
        case .jwt:
            return plural ? OffsendStrings.entityJwts : OffsendStrings.entityJwt
        case .privateKey, .sshPrivateKey:
            return plural ? OffsendStrings.entityPrivateKeys : OffsendStrings.entityPrivateKey
        case .databaseURLWithPassword:
            return plural ? OffsendStrings.entityDatabaseURLs : OffsendStrings.entityDatabaseURL
        case .bearerToken:
            return plural ? OffsendStrings.entityBearerTokens : OffsendStrings.entityBearerToken
        case .highEntropyString:
            return plural ? OffsendStrings.entityHighEntropySecrets : OffsendStrings.entityHighEntropySecret
        }
    }
}
