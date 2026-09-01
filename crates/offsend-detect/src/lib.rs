//! Sensitive-data detection — port of Swift `DetectionCore`.
//!
//! Entity ranges are UTF-8 byte offsets into `DetectionResult.scanned_text`.

mod encoded;
mod engine;
mod masking;
mod overlap;
mod risk;
mod rules;
mod sanitizers;
mod span_refine;
mod types;

pub use engine::{DetectionEngine, EncodedScan};
pub use masking::{mask_text, restore_text, MaskResult, MaskSpan};
pub use risk::{
    assess as assess_risk, weight as risk_weight, RecommendedAction, RiskAssessment, RiskLevel,
    SensitivityTier, NON_SECRET_SCORE_CAP,
};
pub use types::*;
