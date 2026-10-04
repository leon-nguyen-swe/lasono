package com.lasono.track.application.usecase;

import java.util.List;

/** One page of the track list. {@code nextCursor} is {@code null} on the last page. */
public record ListTracksResult(
    List<TrackListItemResult> items,
    String nextCursor
) {}
