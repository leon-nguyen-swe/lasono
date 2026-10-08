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

    /**
     * Like {@link #findNewestAfter}, for the tracks of one owner only. Everyone sees the public ones; the private
     * ones are seen only when {@code viewerId} is the owner. An owner without tracks, or one that does not exist,
     * simply gives an empty list.
     */
    List<TrackSummary> findNewestOfOwnerAfter(UUID ownerId, TrackPosition after, int limit, UUID viewerId);
}
