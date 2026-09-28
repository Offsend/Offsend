use crate::types::{DetectionSource, EntityType, SensitiveEntity};

/// Keep independent spans. Nested matches collapse to the outer (or higher-priority)
/// entity; partial overlaps stay as separate findings. Spans are never expanded.
pub fn resolve(mut entities: Vec<SensitiveEntity>) -> Vec<SensitiveEntity> {
    entities.sort_by(|a, b| {
        a.start
            .cmp(&b.start)
            .then_with(|| b.end.cmp(&a.end))
            .then_with(|| priority(b).cmp(&priority(a)))
    });

    let mut result: Vec<SensitiveEntity> = Vec::new();
    for entity in entities {
        if let Some(i) = result.iter().position(|kept| contains(kept, &entity)) {
            if priority(&entity) > priority(&result[i]) {
                result[i] = entity;
            }
            continue;
        }
        result.push(entity);
    }
    result
}

fn contains(outer: &SensitiveEntity, inner: &SensitiveEntity) -> bool {
    inner.start >= outer.start && inner.end <= outer.end && inner.start < outer.end
}

fn priority(entity: &SensitiveEntity) -> i32 {
    // Match Swift OverlapResolver: high-entropy checked before isSecret.
    if entity.entity_type == EntityType::HighEntropyString {
        return 95;
    }
    if entity.entity_type.is_secret() {
        return 1_000;
    }
    if entity.entity_type == EntityType::CreditCardLike {
        return 120;
    }
    if entity.entity_type == EntityType::IpAddress {
        return 115;
    }
    if entity.entity_type == EntityType::Phone {
        return 85;
    }
    match entity.source {
        DetectionSource::CustomDictionary => 500,
        DetectionSource::Ai => 90,
        DetectionSource::Regex => 100,
        DetectionSource::Secret => 1_000,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn ent(entity_type: EntityType, start: usize, end: usize) -> SensitiveEntity {
        SensitiveEntity {
            id: Uuid::new_v4(),
            entity_type,
            start,
            end,
            value: "x".into(),
            confidence: 1.0,
            source: DetectionSource::Secret,
        }
    }

    #[test]
    fn keeps_adjacent_secrets_without_expanding() {
        let password = ent(EntityType::DatabaseUrlWithPassword, 10, 20);
        let aws = ent(EntityType::AwsAccessKeyId, 40, 60);
        let out = resolve(vec![password, aws]);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].start, 10);
        assert_eq!(out[0].end, 20);
        assert_eq!(out[1].start, 40);
        assert_eq!(out[1].end, 60);
    }

    #[test]
    fn keeps_partial_overlap_as_two_spans() {
        let a = ent(EntityType::DatabaseUrlWithPassword, 0, 12);
        let b = ent(EntityType::AwsAccessKeyId, 8, 20);
        let out = resolve(vec![a, b]);
        assert_eq!(out.len(), 2);
        assert!(out.iter().all(|e| e.end - e.start < 20));
    }

    #[test]
    fn drops_nested_lower_priority() {
        let outer = ent(EntityType::AwsAccessKeyId, 0, 20);
        let mut inner = ent(EntityType::HighEntropyString, 2, 18);
        inner.source = DetectionSource::Regex;
        let out = resolve(vec![outer, inner]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].entity_type, EntityType::AwsAccessKeyId);
        assert_eq!(out[0].start, 0);
        assert_eq!(out[0].end, 20);
    }

    #[test]
    fn nested_secret_wins_over_wider_non_secret() {
        let mut email = ent(EntityType::Email, 0, 30);
        email.source = DetectionSource::Regex;
        let password = ent(EntityType::DatabaseUrlWithPassword, 4, 16);
        let out = resolve(vec![email, password]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].entity_type, EntityType::DatabaseUrlWithPassword);
        assert_eq!(out[0].start, 4);
        assert_eq!(out[0].end, 16);
    }
}
