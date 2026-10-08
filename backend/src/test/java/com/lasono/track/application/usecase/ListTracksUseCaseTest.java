package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import com.lasono.track.application.port.out.TrackSummary;
import com.lasono.track.domain.model.TrackStatus;
import com.lasono.track.domain.model.Visibility;
import com.lasono.track.domain.TrackFixtures;

class ListTracksUseCaseTest {

    private static final Instant START = Instant.parse("2026-10-04T10:00:00Z");

    private InMemoryTrackSummaryReader reader;
    private ListTracksUseCase useCase;

    @BeforeEach
    void setUp() {
        reader = new InMemoryTrackSummaryReader();
        useCase = new ListTracksUseCase(reader);
    }

    @Test
    void returnsAnEmptyPageWhenThereAreNoTracks() {
        ListTracksResult result = useCase.execute(null, null, null);

        assertTrue(result.items().isEmpty());
        assertNull(result.nextCursor());
    }

    @Test
    void returnsTheNewestTrackFirst() {
        addTrack("oldest", 0);
        addTrack("newest", 2);
        addTrack("middle", 1);

        ListTracksResult result = useCase.execute(null, null, null);

        assertEquals(List.of("newest", "middle", "oldest"), titles(result));
    }

    @Test
    void mapsTheTrackFieldsToTheResult() {
        UUID id = UUID.randomUUID();
        reader.add(new TrackSummary(id, TrackFixtures.OWNER.getValue(), "My song", "Some description", Visibility.PUBLIC, TrackStatus.PROCESSING, START, null));

        TrackListItemResult item = useCase.execute(null, null, null).items().get(0);

        assertEquals(id.toString(), item.id());
        assertEquals("My song", item.title());
        assertEquals("Some description", item.description());
        assertEquals("PROCESSING", item.status());
        assertNull(item.durationSeconds(), "a track that is still processing has no duration");
    }

    @Test
    void showsTheDurationInSecondsOfAProcessedTrack() {
        reader.add(new TrackSummary(UUID.randomUUID(), TrackFixtures.OWNER.getValue(), "My song", "", Visibility.PUBLIC, TrackStatus.READY, START, 3500L));

        TrackListItemResult item = useCase.execute(null, null, null).items().get(0);

        assertEquals(3.5, item.durationSeconds());
    }

    @Test
    void hasNoNextCursorWhenEveryTrackFitsInOnePage() {
        addTracks(3);

        ListTracksResult result = useCase.execute(null, 5, null);

        assertEquals(3, result.items().size());
        assertNull(result.nextCursor());
    }

    @Test
    void hasANextCursorWhenMoreTracksExist() {
        addTracks(5);

        ListTracksResult result = useCase.execute(null, 2, null);

        assertEquals(2, result.items().size());
        assertNotNull(result.nextCursor());
    }

    @Test
    void hasNoNextCursorWhenTheLastPageIsExactlyFull() {
        addTracks(4);

        ListTracksResult firstPage = useCase.execute(null, 2, null);
        ListTracksResult lastPage = useCase.execute(firstPage.nextCursor(), 2, null);

        assertNotNull(firstPage.nextCursor());
        assertEquals(2, lastPage.items().size());
        assertNull(lastPage.nextCursor());
    }

    @Test
    void asksForOneMoreTrackThanTheLimitToKnowWhetherAnotherPageExists() {
        addTracks(5);

        useCase.execute(null, 2, null);

        assertEquals(3, reader.lastRequestedLimit());
    }

    @Test
    void followingTheCursorsVisitsEveryTrackOnceInOrderEvenWhenCreationTimesTie() {
        // Pairs of tracks share a creation time, so only the id can order them.
        for (int i = 0; i < 7; i++) {
            addTrack("track " + i, i / 2);
        }
        List<UUID> expected = reader.findNewestAfter(null, 100, null).stream().map(TrackSummary::id).toList();

        List<UUID> visited = new ArrayList<>();
        String cursor = null;
        int pages = 0;
        do {
            ListTracksResult page = useCase.execute(cursor, 2, null);
            page.items().forEach(item -> visited.add(UUID.fromString(item.id())));
            cursor = page.nextCursor();
            pages++;
        } while (cursor != null);

        assertEquals(expected, visited);
        assertEquals(4, pages);
    }

    @Test
    void usesTwentyTracksPerPageByDefault() {
        addTracks(25);

        ListTracksResult result = useCase.execute(null, null, null);

        assertEquals(20, result.items().size());
        assertNotNull(result.nextCursor());
    }

    @Test
    void neverReturnsMoreThanFiftyTracksPerPage() {
        addTracks(60);

        ListTracksResult result = useCase.execute(null, 1000, null);

        assertEquals(50, result.items().size());
        assertNotNull(result.nextCursor());
    }

    @ParameterizedTest
    @ValueSource(ints = {0, -1, -50})
    void rejectsALimitBelowOne(int limit) {
        assertThrows(InvalidPageRequestException.class, () -> useCase.execute(null, limit, null));
    }

    @Test
    void treatsABlankCursorAsTheFirstPage() {
        addTracks(3);

        ListTracksResult result = useCase.execute("  ", 2, null);

        assertEquals(titles(useCase.execute(null, 2, null)), titles(result));
    }

    @Test
    void rejectsAMalformedCursor() {
        assertThrows(InvalidPageRequestException.class, () -> useCase.execute("garbage", 2, null));
    }

    private void addTracks(int count) {
        for (int i = 0; i < count; i++) {
            addTrack("track " + i, i);
        }
    }

    private void addTrack(String title, long secondsAfterStart) {
        reader.add(new TrackSummary(UUID.randomUUID(), TrackFixtures.OWNER.getValue(), title, "", Visibility.PUBLIC, TrackStatus.PROCESSING, START.plusSeconds(secondsAfterStart), null));
    }

    private static List<String> titles(ListTracksResult result) {
        return result.items().stream().map(TrackListItemResult::title).toList();
    }

    private static final UUID ALICE = UUID.fromString("00000000-0000-0000-0000-0000000000a1");
    private static final UUID BOB = UUID.fromString("00000000-0000-0000-0000-0000000000b2");

    private void addTrack(String title, UUID owner, Visibility visibility, int secondsAfterStart) {
        reader.add(new TrackSummary(UUID.randomUUID(), owner, title, "", visibility, TrackStatus.READY,
            START.plusSeconds(secondsAfterStart), null));
    }

    @Test
    void showsTheVisibilityOfEachTrack() {
        addTrack("hidden", ALICE, Visibility.PRIVATE, 1);
        addTrack("shown", ALICE, Visibility.PUBLIC, 0);

        List<TrackListItemResult> items = useCase.execute(null, null, ALICE).items();

        assertEquals(List.of("PRIVATE", "PUBLIC"), items.stream().map(TrackListItemResult::visibility).toList());
    }

    @Test
    void asksTheReaderForTheTracksTheViewerMaySee() {
        useCase.execute(null, null, ALICE);

        assertEquals(ALICE, reader.lastViewerId());
    }

    @Test
    void listsOnlyPublicTracksForSomeoneWhoIsNotLoggedIn() {
        addTrack("alice public", ALICE, Visibility.PUBLIC, 2);
        addTrack("alice private", ALICE, Visibility.PRIVATE, 1);
        addTrack("bob private", BOB, Visibility.PRIVATE, 0);

        assertEquals(List.of("alice public"), titles(useCase.execute(null, null, null)));
    }

    @Test
    void listsPublicTracksAndTheViewersOwnPrivateTracksButNotOthers() {
        addTrack("alice public", ALICE, Visibility.PUBLIC, 3);
        addTrack("alice private", ALICE, Visibility.PRIVATE, 2);
        addTrack("bob private", BOB, Visibility.PRIVATE, 1);
        addTrack("bob public", BOB, Visibility.PUBLIC, 0);

        assertEquals(List.of("alice public", "alice private", "bob public"), titles(useCase.execute(null, null, ALICE)));
        assertEquals(List.of("alice public", "bob private", "bob public"), titles(useCase.execute(null, null, BOB)));
    }
}
