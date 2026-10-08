package com.lasono.track.domain.model;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

import com.lasono.track.domain.exception.TrackVisibilityInvalidException;

class VisibilityTest {

    @Test
    void parse_shouldUnderstandBothValuesInAnyCaseWithSpacesAround() {
        assertEquals(Visibility.PUBLIC, Visibility.parse("PUBLIC"));
        assertEquals(Visibility.PRIVATE, Visibility.parse("private"));
        assertEquals(Visibility.PRIVATE, Visibility.parse("  Private "));
    }

    // Nothing was said, so the track stays as visible as it was before tracks could be private.
    @Test
    void parse_shouldMakeAMissingValuePublic() {
        assertEquals(Visibility.PUBLIC, Visibility.parse(null));
    }

    // A typo must not silently publish a track the owner meant to hide, so anything unclear is refused.
    @Test
    void parse_shouldRefuseAnythingElse() {
        assertThrows(TrackVisibilityInvalidException.class, () -> Visibility.parse(""));
        assertThrows(TrackVisibilityInvalidException.class, () -> Visibility.parse("   "));
        assertThrows(TrackVisibilityInvalidException.class, () -> Visibility.parse("secret"));
        assertThrows(TrackVisibilityInvalidException.class, () -> Visibility.parse("PRIVAT"));
    }
}
