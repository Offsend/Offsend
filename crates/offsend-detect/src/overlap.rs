use crate::types::{DetectionSource, EntityType, SensitiveEntity};

pub fn resolve(mut entities: Vec<SensitiveEntity>) -> Vec<SensitiveEntity> {
    entities.sort_by(|a, b| {
        a.start
            .cmp(&b.start)
            .then_with(|| priority(b).cmp(&priority(a)))
    });

    let mut result: Vec<SensitiveEntity> = Vec::new();
    for entity in entities {
        if let Some(last) = result.last_mut() {
            if entity.start < last.end {
                *last = if priority(&entity) > priority(last) {
                    merge_meta(&entity, last)
                } else {
                    merge_meta(last, &entity)
                };
                continue;
            }
        }
        result.push(entity);
    }
    result
}

fn merge_meta(winner: &SensitiveEntity, other: &SensitiveEntity) -> SensitiveEntity {
    SensitiveEntity {
        id: winner.id,
        entity_type: winner.entity_type,
        start: winner.start.min(other.start),
        end: winner.end.max(other.end),
        value: winner.value.clone(),
        confidence: winner.confidence,
        source: winner.source,
    }
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
