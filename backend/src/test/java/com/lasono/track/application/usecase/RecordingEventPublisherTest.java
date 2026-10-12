package com.lasono.track.application.usecase;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.lasono.shared.event.TrackDeleted;
import com.lasono.shared.event.TrackLiked;
import com.lasono.shared.event.TrackUnliked;

class RecordingEventPublisherTest {

    @Test
    void itKeepsEventsInTheOrderTheyWerePublished() {
        RecordingEventPublisher publisher = new RecordingEventPublisher();
        UUID id1 = UUID.randomUUID();
        UUID id2 = UUID.randomUUID();
        UUID id3 = UUID.randomUUID();
        Instant now = Instant.now();

        TrackLiked first   = new TrackLiked(id1, id2, now);
        TrackUnliked second = new TrackUnliked(id1, id2, now);
        TrackDeleted third  = new TrackDeleted(id3, id2, now);

        publisher.publish(first);
        publisher.publish(second);
        publisher.publish(third);

        assertThat(publisher.published()).containsExactly(first, second, third);
    }

    @Test
    void publishedReturnsCopy_soCallerCannotMutateInternalState() {
        RecordingEventPublisher publisher = new RecordingEventPublisher();
        UUID id = UUID.randomUUID();
        Instant now = Instant.now();

        publisher.publish(new TrackLiked(id, id, now));
        // attempt to mutate the returned list
        var copy = publisher.published();
        assertThat(copy).hasSize(1);
    }
}
