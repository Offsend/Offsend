//! Shrink detector matches to the smallest sensitive span.
//!
//! Whole-value matches stay when the password / token cannot be isolated safely.

use crate::types::{EntityType, SensitiveEntity};

/// Narrow URL-with-password and Bearer matches to the credential only.
/// Credentialed `https://user:pass@host` Url hits become `DatabaseUrlWithPassword`.
pub fn refine_secret_spans(entities: Vec<SensitiveEntity>, text: &str) -> Vec<SensitiveEntity> {
    entities
        .into_iter()
        .map(|entity| refine_one(entity, text))
        .collect()
}

fn refine_one(mut entity: SensitiveEntity, text: &str) -> SensitiveEntity {
    match entity.entity_type {
        EntityType::DatabaseUrlWithPassword => {
            if let Some((start, end)) = password_range_in_url(&entity.value) {
                apply_subspan(&mut entity, start, end);
            }
            entity
        }
        EntityType::BearerToken => {
            if let Some((start, end)) = token_range_in_bearer(&entity.value) {
                apply_subspan(&mut entity, start, end);
            }
            entity
        }
        EntityType::Url => {
            if let Some((start, end)) = password_range_in_url(&entity.value) {
                entity.entity_type = EntityType::DatabaseUrlWithPassword;
                apply_subspan(&mut entity, start, end);
            }
            entity
        }
        _ => {
            let _ = text;
            entity
        }
    }
}

fn apply_subspan(entity: &mut SensitiveEntity, local_start: usize, local_end: usize) {
    let start = entity.start + local_start;
    let end = entity.start + local_end;
    if start >= end || end > entity.start + entity.value.len() {
        return;
    }
    entity.value = entity.value[local_start..local_end].to_string();
    entity.start = start;
    entity.end = end;
}

/// `scheme://user:password@host` → byte range of `password` inside `url`.
/// Empty password or missing userinfo colon → None (keep the full match).
fn password_range_in_url(url: &str) -> Option<(usize, usize)> {
    let scheme = url.find("://")?;
    let userinfo_start = scheme + 3;
    let at = url[userinfo_start..].find('@')?;
    let userinfo = &url[userinfo_start..userinfo_start + at];
    let colon = userinfo.find(':')?;
    let pass_start = userinfo_start + colon + 1;
    let pass_end = userinfo_start + at;
    if pass_start >= pass_end {
        return None;
    }
    Some((pass_start, pass_end))
}

/// `Bearer <token>` → byte range of `<token>` inside `value`.
fn token_range_in_bearer(value: &str) -> Option<(usize, usize)> {
    let prefix_len = if value.len() >= 6 && value[..6].eq_ignore_ascii_case("bearer") {
        6
    } else {
        return None;
    };
    let rest = &value[prefix_len..];
    let skip = rest.find(|c: char| !c.is_whitespace())?;
    let start = prefix_len + skip;
    if start >= value.len() {
        return None;
    }
    Some((start, value.len()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_range_postgres() {
        let url = "postgres://admin:correct-horse@db.internal/prod";
        assert_eq!(
            password_range_in_url(url),
            Some((url.find("correct-horse").unwrap(), url.find('@').unwrap()))
        );
    }

    #[test]
    fn password_range_rejects_empty() {
        assert_eq!(password_range_in_url("postgres://admin:@db.internal/prod"), None);
        assert_eq!(password_range_in_url("postgres://admin@db.internal/prod"), None);
        assert_eq!(password_range_in_url("not-a-url"), None);
    }

    #[test]
    fn bearer_skips_scheme_word() {
        let value = "Bearer abcdefghijklmnopqrstuvwxyz012345";
        assert_eq!(
            token_range_in_bearer(value),
            Some((7, value.len()))
        );
    }
}
