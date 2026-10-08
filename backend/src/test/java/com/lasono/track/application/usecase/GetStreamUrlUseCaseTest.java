package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.domain.InMemoryTrackRepository;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.model.Visibility;

class GetStreamUrlUseCaseTest {

    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final Duration TTL = Duration.ofHours(1);
    private static final UUID STRANGER = UUID.fromString("00000000-0000-0000-0000-0000000000b2");

    private InMemoryTrackRepository trackRepository;
    private GetStreamUrlUseCase useCase;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        useCase = new GetStreamUrlUseCase(
            trackRepository, new FakeStreamUrlSigner(), Clock.fixed(NOW, ZoneOffset.UTC), TTL);
    }

    private UUID aTrack(Visibility visibility) {
        UUID id = UUID.randomUUID();
        trackRepository.save(new Track(new TrackId(id), TrackFixtures.OWNER, "My Song", null, visibility));
        return id;
    }

    @Test
    void execute_shouldGiveTheStreamAddressSignedUntilTheEndOfTheTimeToLive() {
        UUID id = aTrack(Visibility.PUBLIC);
        long expires = NOW.plus(TTL).getEpochSecond();

        StreamUrlResult result = useCase.execute(id, null);

        assertEquals("/api/v1/tracks/" + id + "/stream?expires=" + expires + "&signature=sig-" + id + "-" + expires,
            result.url());
        assertEquals(NOW.plus(TTL), result.expiresAt());
    }

    @Test
    void execute_shouldGiveTheAddressOfAPrivateTrackToItsOwner() {
        UUID id = aTrack(Visibility.PRIVATE);

        StreamUrlResult result = useCase.execute(id, TrackFixtures.OWNER.getValue());

        assertEquals(NOW.plus(TTL), result.expiresAt());
    }

    // Whoever may not see the track cannot get a signature for it, or the signature would be a way in.
    @Test
    void execute_shouldGiveNothingForAPrivateTrackToAStrangerOrToSomeoneNotLoggedIn() {
        UUID id = aTrack(Visibility.PRIVATE);

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, STRANGER));
        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, null));
    }

    @Test
    void execute_shouldThrowWhenTheTrackDoesNotExist() {
        assertThrows(TrackNotFoundException.class, () -> useCase.execute(UUID.randomUUID(), null));
    }
}
