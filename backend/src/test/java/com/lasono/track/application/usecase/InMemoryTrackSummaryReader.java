package com.lasono.track.application.usecase;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

import com.lasono.track.application.port.out.TrackPosition;
import com.lasono.track.application.port.out.TrackSummary;
import com.lasono.track.application.port.out.TrackSummaryReader;
import com.lasono.track.domain.model.Visibility;

/**
 * In-memory stand-in for the database. It lists the public tracks and the private ones of the viewer, sorts
 * newest first and returns the tracks that come strictly after the given position, the way the real keyset query does. Ids are compared as
 * unsigned bytes like PostgreSQL does; {@code UUID.compareTo} is signed and would order them
 * differently.
 */
class InMemoryTrackSummaryReader implements TrackSummaryReader {

    private static final Comparator<TrackSummary> NEWEST_FIRST =
        Comparator.comparing(TrackSummary::createdAt)
            .thenComparing(TrackSummary::id, InMemoryTrackSummaryReader::compareUnsigned)
            .reversed();

    private final List<TrackSummary> summaries = new ArrayList<>();
    private int lastRequestedLimit;
    private UUID lastViewerId;

    void add(TrackSummary summary) {
        summaries.add(summary);
    }

    int lastRequestedLimit() {
        return lastRequestedLimit;
    }

    UUID lastViewerId() {
        return lastViewerId;
    }

    @Override
    public List<TrackSummary> findNewestAfter(TrackPosition after, int limit, UUID viewerId) {
        lastRequestedLimit = limit;
        lastViewerId = viewerId;
        return summaries.stream()
            .filter(summary -> summary.visibility() == Visibility.PUBLIC || summary.ownerId().equals(viewerId))
            .sorted(NEWEST_FIRST)
            .filter(summary -> after == null || comesAfter(summary, after))
            .limit(limit)
            .toList();
    }

    private static boolean comesAfter(TrackSummary summary, TrackPosition position) {
        int byTime = summary.createdAt().compareTo(position.createdAt());
        if (byTime != 0) {
            return byTime < 0;
        }
        return compareUnsigned(summary.id(), position.id()) < 0;
    }

    private static int compareUnsigned(UUID a, UUID b) {
        int byHighBits = Long.compareUnsigned(a.getMostSignificantBits(), b.getMostSignificantBits());
        return byHighBits != 0
            ? byHighBits
            : Long.compareUnsigned(a.getLeastSignificantBits(), b.getLeastSignificantBits());
    }
}
