package com.lasono.track.application.port.out;

import com.lasono.shared.event.DomainEvent;

/** Publishes a domain event to any interested listeners in the same application. */
public interface EventPublisher {
    void publish(DomainEvent event);
}
