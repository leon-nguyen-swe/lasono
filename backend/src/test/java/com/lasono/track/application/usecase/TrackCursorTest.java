package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;
import java.util.stream.Stream;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

import com.lasono.track.application.port.out.TrackPosition;

class TrackCursorTest {

    private static final UUID ID = UUID.fromString("3f2b8a52-8f5e-4c1d-9a55-0b7f4f6c2d10");

    @Test
    void decodesWhatItEncoded() {
        TrackPosition position = new TrackPosition(Instant.parse("2026-10-04T10:15:30.123456Z"), ID);

        assertEquals(position, TrackCursor.decode(TrackCursor.encode(position)));
    }

    @Test
    void keepsMicrosecondPrecisionBecauseThatIsWhatPostgresStores() {
        TrackPosition position = new TrackPosition(Instant.EPOCH.plusNanos(1_000), ID);

        TrackPosition decoded = TrackCursor.decode(TrackCursor.encode(position));

        assertEquals(position.createdAt(), decoded.createdAt());
    }

    @Test
    void keepsInstantsBeforeTheEpoch() {
        TrackPosition position = new TrackPosition(Instant.parse("1969-12-31T23:59:59.999999Z"), ID);

        assertEquals(position, TrackCursor.decode(TrackCursor.encode(position)));
    }

    @Test
    void producesAnOpaqueUrlSafeString() {
        String cursor = TrackCursor.encode(new TrackPosition(Instant.parse("2026-10-04T10:15:30Z"), ID));

        assertTrue(cursor.matches("[A-Za-z0-9_-]+"), "should only use URL-safe characters: " + cursor);
        assertFalse(cursor.contains(ID.toString()), "should not show the id in clear text");
    }

    static Stream<String> malformedCursors() {
        return Stream.of(
            "",
            "   ",
            "not a cursor",
            "%%%",
            base64("no separator"),
            base64("abc:" + ID),
            base64("123:not-a-uuid"),
            base64(":" + ID),
            base64("99999999999999999999:" + ID)
        );
    }

    @ParameterizedTest
    @MethodSource("malformedCursors")
    void rejectsAMalformedCursor(String cursor) {
        InvalidPageRequestException error =
            assertThrows(InvalidPageRequestException.class, () -> TrackCursor.decode(cursor));

        assertEquals("Invalid cursor", error.getMessage());
    }

    private static String base64(String text) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(text.getBytes(StandardCharsets.UTF_8));
    }
}
