package com.lasono.track.infrastructure.event;

import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

import com.lasono.shared.event.DomainEvent;
import com.lasono.track.application.port.out.EventPublisher;

/** Delegates to Spring's {@link ApplicationEventPublisher} so events reach {@code @EventListener} handlers. */
@Component
public class SpringEventPublisher implements EventPublisher {

    private final ApplicationEventPublisher publisher;

    public SpringEventPublisher(ApplicationEventPublisher publisher) {
        this.publisher = publisher;
    }

    @Override
    public void publish(DomainEvent event) {
        publisher.publishEvent(event);
    }
}
