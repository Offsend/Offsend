use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SealError {
    #[error("Plaintext is {byte_count} bytes; seal limit is {limit} bytes.")]
    PlaintextTooLarge { byte_count: usize, limit: usize },

    #[error("Invalid seal token format.")]
    InvalidTokenFormat,

    #[error("Unsupported seal token version: {0}.")]
    UnsupportedTokenVersion(String),

    #[error("Failed to decrypt seal token (wrong key or tampered token).")]
    DecryptionFailed,

    #[error("Failed to encrypt seal token.")]
    EncryptionFailed,

    #[error("Invalid seal key: {0}")]
    InvalidKey(String),
}
