package com.lasono.track.application.port.out;

import java.util.List;
import java.util.UUID;

public interface TrackSummaryReader {

    /**
     * Returns at most {@code limit} tracks, newest first (by creation time, then by id), that come
     * strictly after {@code after}. A {@code null} {@code after} starts from the newest track.
     * Only tracks the viewer may see are listed: the public ones, and the private ones of {@code viewerId},
     * who is null when nobody is logged in. The filter is part of the query, so a page is always full
     * and the position of the last track still leads to the next one.
     */
    List<TrackSummary> findNewestAfter(TrackPosition after, int limit, UUID viewerId);
}
