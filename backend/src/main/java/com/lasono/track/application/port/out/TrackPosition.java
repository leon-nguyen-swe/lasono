package com.lasono.track.application.port.out;

import java.time.Instant;
import java.util.UUID;

/**
 * Where a page of the newest-first track list stops: the (createdAt, id) of its last track. The
 * next page starts right after it. {@code id} breaks ties between tracks created at the same time.
 */
public record TrackPosition(Instant createdAt, UUID id) {
}
