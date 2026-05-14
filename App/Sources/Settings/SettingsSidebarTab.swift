enum SettingsSidebarTab: String, CaseIterable, Identifiable {
    case general
    case hotkeys
    case detection
    case masking
    case privacy
    case license
    #if DEBUG
    case developer
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return OffsendStrings.settingsTabGeneral
        case .hotkeys:
            return OffsendStrings.settingsTabHotkeys
        case .detection:
            return OffsendStrings.settingsTabDetection
        case .masking:
            return OffsendStrings.settingsTabMasking
        case .privacy:
            return OffsendStrings.settingsTabPrivacy
        case .license:
            return OffsendStrings.settingsTabLicense
        #if DEBUG
        case .developer:
            return OffsendStrings.settingsTabDeveloper
        #endif
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return OffsendStrings.settingsSubtitleGeneral
        case .hotkeys:
            return OffsendStrings.settingsSubtitleHotkeys
        case .detection:
            return OffsendStrings.settingsSubtitleDetection
        case .masking:
            return OffsendStrings.settingsSubtitleMasking
        case .privacy:
            return OffsendStrings.settingsSubtitlePrivacy
        case .license:
            return OffsendStrings.settingsSubtitleLicense
        #if DEBUG
        case .developer:
            return OffsendStrings.settingsSubtitleDeveloper
        #endif
        }
    }

    var sfSymbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .hotkeys:
            return "command"
        case .detection:
            return "scope"
        case .masking:
            return "theatermasks"
        case .privacy:
            return "lock.shield"
        case .license:
            return "crown"
        #if DEBUG
        case .developer:
            return "ladybug"
        #endif
        }
    }
}
