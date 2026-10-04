package com.lasono.track.application.port.out;

import java.util.List;

public interface TrackSummaryReader {

    /**
     * Returns at most {@code limit} tracks, newest first (by creation time, then by id), that come
     * strictly after {@code after}. A {@code null} {@code after} starts from the newest track.
     */
    List<TrackSummary> findNewestAfter(TrackPosition after, int limit);
}
