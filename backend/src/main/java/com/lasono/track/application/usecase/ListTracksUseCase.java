package com.lasono.track.application.usecase;

import java.util.List;
import java.util.UUID;
import java.util.function.BiFunction;

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
        return page(cursor, limit, (after, fetchSize) -> trackSummaryReader.findNewestAfter(after, fetchSize, viewerId));
    }

    /** The tracks of one owner, newest first. The owner sees their private tracks too; nobody else does. */
    public ListTracksResult executeForOwner(UUID ownerId, String cursor, Integer limit, UUID viewerId) {
        return page(cursor, limit,
            (after, fetchSize) -> trackSummaryReader.findNewestOfOwnerAfter(ownerId, after, fetchSize, viewerId));
    }

    private ListTracksResult page(String cursor, Integer limit, BiFunction<TrackPosition, Integer, List<TrackSummary>> fetch) {
        int pageSize = pageSize(limit);
        TrackPosition after = cursor == null || cursor.isBlank() ? null : TrackCursor.decode(cursor);

        // Asking for one track more than the page tells us whether another page exists,
        // without a separate COUNT query.
        List<TrackSummary> found = fetch.apply(after, pageSize + 1);

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
            summary.ownerId().toString(),
            summary.title(),
            summary.description(),
            summary.visibility().name(),
            summary.status().name(),
            summary.durationMs() != null ? summary.durationMs() / 1000.0 : null
        );
    }
}
