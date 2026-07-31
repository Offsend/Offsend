use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EntityType {
    Email,
    Phone,
    Money,
    Url,
    IpAddress,
    InternalDomain,
    ContractId,
    InvoiceId,
    OrderId,
    ApiKeyGeneric,
    OpenAIAPIKey,
    AwsAccessKeyId,
    GithubToken,
    SlackToken,
    StripeKey,
    Jwt,
    PrivateKey,
    SshPrivateKey,
    DatabaseUrlWithPassword,
    BearerToken,
    HighEntropyString,
    CreditCardLike,
    Iban,
    CustomClient,
    CustomCompany,
    CustomProject,
    CustomSensitiveTerm,
    CustomInternalDomain,
    PersonName,
    StreetAddress,
    GovernmentId,
}

impl EntityType {
    pub fn all() -> &'static [EntityType] {
        &ALL_TYPES
    }

    pub fn placeholder_prefix(self) -> &'static str {
        use EntityType::*;
        match self {
            Email => "EMAIL",
            Phone => "PHONE",
            Money => "AMOUNT",
            Url => "URL",
            IpAddress => "IP",
            InternalDomain | CustomInternalDomain => "INTERNAL_DOMAIN",
            ContractId => "CONTRACT",
            InvoiceId => "INVOICE",
            OrderId => "ORDER",
            CreditCardLike => "CARD",
            Iban => "IBAN",
            CustomClient => "CLIENT",
            CustomCompany => "COMPANY",
            CustomProject => "PROJECT",
            CustomSensitiveTerm => "CUSTOM",
            PersonName => "PERSON",
            StreetAddress => "ADDRESS",
            GovernmentId => "GOV_ID",
            _ => "SECRET",
        }
    }

    pub fn is_secret(self) -> bool {
        use EntityType::*;
        matches!(
            self,
            ApiKeyGeneric
                | OpenAIAPIKey
                | AwsAccessKeyId
                | GithubToken
                | SlackToken
                | StripeKey
                | Jwt
                | PrivateKey
                | SshPrivateKey
                | DatabaseUrlWithPassword
                | BearerToken
                | HighEntropyString
        )
    }

    pub fn counts_as_critical_secret(self) -> bool {
        self.is_secret() && self != EntityType::HighEntropyString
    }

    pub fn from_swift_name(name: &str) -> Option<Self> {
        use EntityType::*;
        Some(match name {
            "email" => Email,
            "phone" => Phone,
            "money" => Money,
            "url" => Url,
            "ipAddress" => IpAddress,
            "internalDomain" => InternalDomain,
            "contractId" => ContractId,
            "invoiceId" => InvoiceId,
            "orderId" => OrderId,
            "apiKeyGeneric" => ApiKeyGeneric,
            "openAIAPIKey" => OpenAIAPIKey,
            "awsAccessKeyId" => AwsAccessKeyId,
            "githubToken" => GithubToken,
            "slackToken" => SlackToken,
            "stripeKey" => StripeKey,
            "jwt" => Jwt,
            "privateKey" => PrivateKey,
            "sshPrivateKey" => SshPrivateKey,
            "databaseURLWithPassword" => DatabaseUrlWithPassword,
            "bearerToken" => BearerToken,
            "highEntropyString" => HighEntropyString,
            "creditCardLike" => CreditCardLike,
            "iban" => Iban,
            "customClient" => CustomClient,
            "customCompany" => CustomCompany,
            "customProject" => CustomProject,
            "customSensitiveTerm" => CustomSensitiveTerm,
            "customInternalDomain" => CustomInternalDomain,
            "personName" => PersonName,
            "streetAddress" => StreetAddress,
            "governmentId" => GovernmentId,
            _ => return None,
        })
    }

    /// Swift `SensitiveEntityType` raw value (camelCase).
    pub fn swift_name(self) -> &'static str {
        use EntityType::*;
        match self {
            Email => "email",
            Phone => "phone",
            Money => "money",
            Url => "url",
            IpAddress => "ipAddress",
            InternalDomain => "internalDomain",
            ContractId => "contractId",
            InvoiceId => "invoiceId",
            OrderId => "orderId",
            ApiKeyGeneric => "apiKeyGeneric",
            OpenAIAPIKey => "openAIAPIKey",
            AwsAccessKeyId => "awsAccessKeyId",
            GithubToken => "githubToken",
            SlackToken => "slackToken",
            StripeKey => "stripeKey",
            Jwt => "jwt",
            PrivateKey => "privateKey",
            SshPrivateKey => "sshPrivateKey",
            DatabaseUrlWithPassword => "databaseURLWithPassword",
            BearerToken => "bearerToken",
            HighEntropyString => "highEntropyString",
            CreditCardLike => "creditCardLike",
            Iban => "iban",
            CustomClient => "customClient",
            CustomCompany => "customCompany",
            CustomProject => "customProject",
            CustomSensitiveTerm => "customSensitiveTerm",
            CustomInternalDomain => "customInternalDomain",
            PersonName => "personName",
            StreetAddress => "streetAddress",
            GovernmentId => "governmentId",
        }
    }
}

const ALL_TYPES: [EntityType; 31] = [
    EntityType::Email,
    EntityType::Phone,
    EntityType::Money,
    EntityType::Url,
    EntityType::IpAddress,
    EntityType::InternalDomain,
    EntityType::ContractId,
    EntityType::InvoiceId,
    EntityType::OrderId,
    EntityType::ApiKeyGeneric,
    EntityType::OpenAIAPIKey,
    EntityType::AwsAccessKeyId,
    EntityType::GithubToken,
    EntityType::SlackToken,
    EntityType::StripeKey,
    EntityType::Jwt,
    EntityType::PrivateKey,
    EntityType::SshPrivateKey,
    EntityType::DatabaseUrlWithPassword,
    EntityType::BearerToken,
    EntityType::HighEntropyString,
    EntityType::CreditCardLike,
    EntityType::Iban,
    EntityType::CustomClient,
    EntityType::CustomCompany,
    EntityType::CustomProject,
    EntityType::CustomSensitiveTerm,
    EntityType::CustomInternalDomain,
    EntityType::PersonName,
    EntityType::StreetAddress,
    EntityType::GovernmentId,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DetectionSource {
    Regex,
    Secret,
    CustomDictionary,
    Ai,
}

impl DetectionSource {
    pub fn from_swift_name(name: &str) -> Option<Self> {
        Some(match name {
            "regex" => Self::Regex,
            "secret" => Self::Secret,
            "customDictionary" => Self::CustomDictionary,
            "ai" => Self::Ai,
            _ => return None,
        })
    }

    pub fn swift_name(self) -> &'static str {
        match self {
            Self::Regex => "regex",
            Self::Secret => "secret",
            Self::CustomDictionary => "customDictionary",
            Self::Ai => "ai",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CustomDictionaryKind {
    Client,
    Company,
    Project,
    SensitiveTerm,
    InternalDomain,
    Regex,
}

impl CustomDictionaryKind {
    pub fn entity_type(self) -> EntityType {
        match self {
            Self::Client => EntityType::CustomClient,
            Self::Company => EntityType::CustomCompany,
            Self::Project => EntityType::CustomProject,
            Self::SensitiveTerm | Self::Regex => EntityType::CustomSensitiveTerm,
            Self::InternalDomain => EntityType::CustomInternalDomain,
        }
    }

    pub fn from_swift_name(name: &str) -> Option<Self> {
        Some(match name {
            "client" => Self::Client,
            "company" => Self::Company,
            "project" => Self::Project,
            "sensitiveTerm" => Self::SensitiveTerm,
            "internalDomain" => Self::InternalDomain,
            "regex" => Self::Regex,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CustomDictionaryItem {
    pub kind: CustomDictionaryKind,
    pub value: String,
}

#[derive(Debug, Clone)]
pub struct DetectionOptions {
    pub enabled_types: HashSet<EntityType>,
    pub maximum_length: usize,
    pub honor_inline_ignore: bool,
    pub custom_dictionaries: Vec<CustomDictionaryItem>,
}

impl Default for DetectionOptions {
    fn default() -> Self {
        Self {
            enabled_types: EntityType::all().iter().copied().collect(),
            maximum_length: 50_000,
            honor_inline_ignore: false,
            custom_dictionaries: Vec::new(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct DetectionRequest {
    pub text: String,
    pub options: DetectionOptions,
}

impl DetectionRequest {
    pub fn new(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            options: DetectionOptions::default(),
        }
    }
}

/// UTF-8 byte offsets into `DetectionResult.scanned_text`.
#[derive(Debug, Clone, PartialEq)]
pub struct SensitiveEntity {
    pub id: uuid::Uuid,
    pub entity_type: EntityType,
    pub start: usize,
    pub end: usize,
    pub value: String,
    pub confidence: f64,
    pub source: DetectionSource,
}

#[derive(Debug, Clone)]
pub struct DetectionResult {
    pub entities: Vec<SensitiveEntity>,
    pub scanned_text: String,
    pub was_truncated: bool,
    pub scanned_character_count: usize,
}
