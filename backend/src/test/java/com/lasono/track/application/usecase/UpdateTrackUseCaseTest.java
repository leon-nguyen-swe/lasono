package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.domain.InMemoryTrackRepository;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.exception.TrackTitleInvalidException;
import com.lasono.track.domain.exception.TrackVisibilityInvalidException;
import com.lasono.track.domain.model.Visibility;

class UpdateTrackUseCaseTest {

    private static final UUID OWNER = TrackFixtures.OWNER.getValue();
    private static final UUID STRANGER = UUID.fromString("00000000-0000-0000-0000-0000000000b2");

    private InMemoryTrackRepository trackRepository;
    private UpdateTrackUseCase useCase;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        useCase = new UpdateTrackUseCase(trackRepository);
    }

    private UUID aTrack(Visibility visibility) {
        UUID id = UUID.randomUUID();
        trackRepository.save(new Track(new TrackId(id), TrackFixtures.OWNER, "Old title", "old", visibility));
        return id;
    }

    private Track stored(UUID id) {
        return trackRepository.findById(new TrackId(id)).orElseThrow();
    }

    @Test
    void execute_shouldChangeOnlyTheTitleWhenOnlyTheTitleIsGiven() {
        UUID id = aTrack(Visibility.PRIVATE);

        GetTrackResult result = useCase.execute(new UpdateTrackCommand(id, OWNER, "New title", null, null));

        assertEquals("New title", result.title());
        assertEquals("old", result.description());
        assertEquals("PRIVATE", result.visibility());
        assertEquals("New title", stored(id).getTitle());
        assertEquals("old", stored(id).getDescription());
        assertEquals(Visibility.PRIVATE, stored(id).getVisibility());
    }

    @Test
    void execute_shouldChangeEveryFieldThatIsGiven() {
        UUID id = aTrack(Visibility.PUBLIC);

        GetTrackResult result = useCase.execute(new UpdateTrackCommand(id, OWNER, "New title", "new", "private"));

        assertEquals("New title", result.title());
        assertEquals("new", result.description());
        assertEquals("PRIVATE", result.visibility());
        assertEquals(Visibility.PRIVATE, stored(id).getVisibility());
    }

    @Test
    void execute_shouldChangeNothingWhenNoFieldIsGiven() {
        UUID id = aTrack(Visibility.PRIVATE);

        GetTrackResult result = useCase.execute(new UpdateTrackCommand(id, OWNER, null, null, null));

        assertEquals("Old title", result.title());
        assertEquals("old", result.description());
        assertEquals("PRIVATE", result.visibility());
    }

    // null means "leave it", so the only way to clear a description is to send an empty one.
    @Test
    void execute_shouldClearTheDescriptionWhenAnEmptyOneIsGiven() {
        UUID id = aTrack(Visibility.PUBLIC);

        useCase.execute(new UpdateTrackCommand(id, OWNER, null, "", null));

        assertEquals("", stored(id).getDescription());
    }

    @Test
    void execute_shouldRefuseABlankTitleAndChangeNothing() {
        UUID id = aTrack(Visibility.PUBLIC);

        assertThrows(TrackTitleInvalidException.class,
            () -> useCase.execute(new UpdateTrackCommand(id, OWNER, "   ", "new", "PRIVATE")));

        assertEquals("Old title", stored(id).getTitle());
        assertEquals("old", stored(id).getDescription());
        assertEquals(Visibility.PUBLIC, stored(id).getVisibility());
    }

    // An unclear visibility must not quietly publish a track, nor half-apply the other fields.
    @Test
    void execute_shouldRefuseAnUnknownOrEmptyVisibilityAndChangeNothing() {
        UUID id = aTrack(Visibility.PRIVATE);

        assertThrows(TrackVisibilityInvalidException.class,
            () -> useCase.execute(new UpdateTrackCommand(id, OWNER, "New title", null, "secret")));
        assertThrows(TrackVisibilityInvalidException.class,
            () -> useCase.execute(new UpdateTrackCommand(id, OWNER, null, null, "")));

        assertEquals("Old title", stored(id).getTitle());
        assertEquals(Visibility.PRIVATE, stored(id).getVisibility());
    }

    // D7: a track you can see but do not own is "not yours" (403).
    @Test
    void execute_shouldRefuseAStrangerWhoCanSeeThePublicTrackAndChangeNothing() {
        UUID id = aTrack(Visibility.PUBLIC);

        assertThrows(TrackNotOwnedException.class,
            () -> useCase.execute(new UpdateTrackCommand(id, STRANGER, "Hijacked", null, "PRIVATE")));

        assertEquals("Old title", stored(id).getTitle());
        assertEquals(Visibility.PUBLIC, stored(id).getVisibility());
    }

    // D7: a track you cannot see is "not found" (404), so a private track of someone else does not show itself.
    @Test
    void execute_shouldAnswerNotFoundForAStrangerAndAPrivateTrack() {
        UUID id = aTrack(Visibility.PRIVATE);

        assertThrows(TrackNotFoundException.class,
            () -> useCase.execute(new UpdateTrackCommand(id, STRANGER, "Hijacked", null, null)));

        assertEquals("Old title", stored(id).getTitle());
    }

    @Test
    void execute_shouldAnswerNotFoundForATrackThatDoesNotExist() {
        assertThrows(TrackNotFoundException.class,
            () -> useCase.execute(new UpdateTrackCommand(UUID.randomUUID(), OWNER, "Title", null, null)));
    }
}
