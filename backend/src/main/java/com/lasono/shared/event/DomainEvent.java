package com.lasono.shared.event;

import java.time.Instant;

/** Something that has already happened. Named in the past tense, carries ids and the time, nothing else. */
public interface DomainEvent {
    Instant occurredAt();
}
