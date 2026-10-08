package com.lasono.track.application.usecase;

import java.util.List;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.TrackPosition;
import com.lasono.track.application.port.out.TrackSummary;
import com.lasono.track.application.port.out.TrackSummaryReader;

@Component
public class ListTracksUseCase {

    static final int DEFAULT_LIMIT = 20;
    static final int MAX_LIMIT = 50;

    private final TrackSummaryReader trackSummaryReader;

    public ListTracksUseCase(TrackSummaryReader trackSummaryReader) {
        this.trackSummaryReader = trackSummaryReader;
    }

    public ListTracksResult execute(String cursor, Integer limit, UUID viewerId) {
        int pageSize = pageSize(limit);
        TrackPosition after = cursor == null || cursor.isBlank() ? null : TrackCursor.decode(cursor);

        // Asking for one track more than the page tells us whether another page exists,
        // without a separate COUNT query.
        List<TrackSummary> found = trackSummaryReader.findNewestAfter(after, pageSize + 1, viewerId);

        boolean hasNextPage = found.size() > pageSize;
        List<TrackSummary> page = hasNextPage ? found.subList(0, pageSize) : found;
        String nextCursor = hasNextPage ? cursorAfter(page.get(page.size() - 1)) : null;

        return new ListTracksResult(page.stream().map(ListTracksUseCase::toItem).toList(), nextCursor);
    }

    private static int pageSize(Integer limit) {
        if (limit == null) {
            return DEFAULT_LIMIT;
        }
        if (limit < 1) {
            throw new InvalidPageRequestException("limit must be at least 1");
        }
        return Math.min(limit, MAX_LIMIT);
    }

    private static String cursorAfter(TrackSummary lastTrackOfPage) {
        return TrackCursor.encode(new TrackPosition(lastTrackOfPage.createdAt(), lastTrackOfPage.id()));
    }

    private static TrackListItemResult toItem(TrackSummary summary) {
        return new TrackListItemResult(
            summary.id().toString(),
            summary.title(),
            summary.description(),
            summary.visibility().name(),
            summary.status().name(),
            summary.durationMs() != null ? summary.durationMs() / 1000.0 : null
        );
    }
}
