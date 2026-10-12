package com.lasono.track.application.usecase;

import java.util.ArrayList;
import java.util.List;

import com.lasono.shared.event.DomainEvent;
import com.lasono.track.application.port.out.EventPublisher;

/** Test double that records published events in the order they were published. */
class RecordingEventPublisher implements EventPublisher {

    private final List<DomainEvent> published = new ArrayList<>();

    @Override
    public void publish(DomainEvent event) {
        published.add(event);
    }

    public List<DomainEvent> published() {
        return List.copyOf(published);
    }
}
