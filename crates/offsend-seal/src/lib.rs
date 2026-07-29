//! Reversible Offsend seal tokens: `{{TYPE:v1.<base64url>}}`.
//!
//! Wire-compatible with Swift `MaskingCore.SealEngine` (AES-256-GCM,
//! AAD = UTF-8 `TYPE`, CryptoKit `SealedBox.combined` layout).

mod engine;
mod error;
mod token;

pub use engine::{SealEngine, SealResult, SealSpan};
pub use error::SealError;
pub use token::SealTokenDetector;
