package com.lasono.track.domain.model;

import java.util.Locale;

import com.lasono.track.domain.exception.TrackVisibilityInvalidException;

public enum Visibility {
    PUBLIC,
    PRIVATE;

    /** A track is public unless the owner says otherwise, so a missing value means {@link #PUBLIC}. */
    public static Visibility parse(String value) {
        if (value == null) {
            return PUBLIC;
        }
        // Not valueOf(): its error is not ours, and it would not accept lower case or spaces.
        return switch (value.trim().toUpperCase(Locale.ROOT)) {
            case "PUBLIC" -> PUBLIC;
            case "PRIVATE" -> PRIVATE;
            default -> throw new TrackVisibilityInvalidException("Visibility must be PUBLIC or PRIVATE");
        };
    }
}
