//! Risk scoring — port of Swift `RiskScoringEngine`.

use crate::types::EntityType;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SensitivityTier {
    Neutral,
    SecretsConfig,
    DocsOrTests,
}

impl SensitivityTier {
    pub fn from_swift_name(name: &str) -> Option<Self> {
        Some(match name {
            "neutral" => Self::Neutral,
            "secretsConfig" => Self::SecretsConfig,
            "docsOrTests" => Self::DocsOrTests,
            _ => return None,
        })
    }

    pub fn swift_name(self) -> &'static str {
        match self {
            Self::Neutral => "neutral",
            Self::SecretsConfig => "secretsConfig",
            Self::DocsOrTests => "docsOrTests",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RiskLevel {
    Low,
    Medium,
    High,
    Critical,
}

impl RiskLevel {
    pub fn swift_name(self) -> &'static str {
        match self {
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
            Self::Critical => "critical",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecommendedAction {
    Allow,
    Warn,
    Mask,
    Block,
}

impl RecommendedAction {
    pub fn swift_name(self) -> &'static str {
        match self {
            Self::Allow => "allow",
            Self::Warn => "warn",
            Self::Mask => "mask",
            Self::Block => "block",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RiskAssessment {
    pub score: i32,
    pub level: RiskLevel,
    pub recommended_action: RecommendedAction,
    pub has_critical_secret: bool,
}

pub const NON_SECRET_SCORE_CAP: i32 = 75;

pub fn assess(entity_types: &[EntityType], tier: SensitivityTier) -> RiskAssessment {
    if entity_types.is_empty() {
        return RiskAssessment {
            score: 0,
            level: RiskLevel::Low,
            recommended_action: RecommendedAction::Allow,
            has_critical_secret: false,
        };
    }

    let raw_score: i32 = entity_types.iter().map(|t| weight(*t)).sum();
    let has_confirmed_secret = entity_types.iter().any(|t| t.counts_as_critical_secret());

    if has_confirmed_secret {
        return RiskAssessment {
            score: raw_score.max(100),
            level: RiskLevel::Critical,
            recommended_action: RecommendedAction::Block,
            has_critical_secret: true,
        };
    }

    match tier {
        SensitivityTier::Neutral => non_secret_assessment(raw_score.min(NON_SECRET_SCORE_CAP)),
        SensitivityTier::SecretsConfig => escalated(non_secret_assessment(raw_score)),
        SensitivityTier::DocsOrTests => {
            capped_at_warn(non_secret_assessment(raw_score.min(NON_SECRET_SCORE_CAP)))
        }
    }
}

pub fn weight(entity_type: EntityType) -> i32 {
    use EntityType::*;
    match entity_type {
        Email | Phone | Money | InvoiceId => 20,
        Url => 10,
        IpAddress => 15,
        InternalDomain => 35,
        ContractId | OrderId => 25,
        CustomClient | CustomCompany | CustomProject | CustomSensitiveTerm | CustomInternalDomain => {
            40
        }
        CreditCardLike => 80,
        Iban => 60,
        PersonName | StreetAddress | GovernmentId => 25,
        Jwt => 80,
        ApiKeyGeneric | OpenAIAPIKey | AwsAccessKeyId | GithubToken | SlackToken | StripeKey
        | PrivateKey | SshPrivateKey | DatabaseUrlWithPassword | BearerToken => 100,
        HighEntropyString => 55,
    }
}

fn non_secret_assessment(score: i32) -> RiskAssessment {
    match score {
        0..=19 => RiskAssessment {
            score,
            level: RiskLevel::Low,
            recommended_action: RecommendedAction::Allow,
            has_critical_secret: false,
        },
        20..=49 => RiskAssessment {
            score,
            level: RiskLevel::Medium,
            recommended_action: RecommendedAction::Warn,
            has_critical_secret: false,
        },
        _ => RiskAssessment {
            score,
            level: RiskLevel::High,
            recommended_action: RecommendedAction::Mask,
            has_critical_secret: false,
        },
    }
}

fn escalated(base: RiskAssessment) -> RiskAssessment {
    match base.level {
        RiskLevel::Low => RiskAssessment {
            score: base.score,
            level: RiskLevel::Medium,
            recommended_action: RecommendedAction::Warn,
            has_critical_secret: false,
        },
        RiskLevel::Medium => RiskAssessment {
            score: base.score,
            level: RiskLevel::High,
            recommended_action: RecommendedAction::Mask,
            has_critical_secret: false,
        },
        RiskLevel::High => RiskAssessment {
            score: base.score,
            level: RiskLevel::Critical,
            recommended_action: RecommendedAction::Block,
            has_critical_secret: false,
        },
        RiskLevel::Critical => base,
    }
}

fn capped_at_warn(base: RiskAssessment) -> RiskAssessment {
    match base.recommended_action {
        RecommendedAction::Mask | RecommendedAction::Block => RiskAssessment {
            score: base.score,
            level: RiskLevel::Medium,
            recommended_action: RecommendedAction::Warn,
            has_critical_secret: base.has_critical_secret,
        },
        RecommendedAction::Allow | RecommendedAction::Warn => base,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn critical_secret_blocks() {
        let a = assess(&[EntityType::OpenAIAPIKey], SensitivityTier::DocsOrTests);
        assert_eq!(a.recommended_action, RecommendedAction::Block);
        assert!(a.has_critical_secret);
        assert!(a.score >= 100);
    }

    #[test]
    fn email_is_medium_warn() {
        let a = assess(&[EntityType::Email], SensitivityTier::Neutral);
        assert_eq!(a.level, RiskLevel::Medium);
        assert_eq!(a.recommended_action, RecommendedAction::Warn);
    }
}
