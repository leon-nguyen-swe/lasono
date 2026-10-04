package com.lasono.track.application.usecase;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;

import com.lasono.track.application.port.out.TrackPosition;

/**
 * Turns a {@link TrackPosition} into the opaque cursor string clients send back to get the next
 * page, and back. The time is kept in microseconds because that is the precision PostgreSQL
 * stores, so a cursor never points between two stored values.
 */
public final class TrackCursor {

    private static final String INVALID = "Invalid cursor";

    private TrackCursor() {
    }

    public static String encode(TrackPosition position) {
        long micros = ChronoUnit.MICROS.between(Instant.EPOCH, position.createdAt());
        String raw = micros + ":" + position.id();
        return Base64.getUrlEncoder().withoutPadding().encodeToString(raw.getBytes(StandardCharsets.UTF_8));
    }

    public static TrackPosition decode(String cursor) {
        try {
            String raw = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.UTF_8);
            int separator = raw.indexOf(':');
            if (separator < 0) {
                throw new InvalidPageRequestException(INVALID);
            }
            long micros = Long.parseLong(raw.substring(0, separator));
            UUID id = UUID.fromString(raw.substring(separator + 1));
            return new TrackPosition(Instant.EPOCH.plus(micros, ChronoUnit.MICROS), id);
        } catch (IllegalArgumentException e) {
            throw new InvalidPageRequestException(INVALID);
        }
    }
}
