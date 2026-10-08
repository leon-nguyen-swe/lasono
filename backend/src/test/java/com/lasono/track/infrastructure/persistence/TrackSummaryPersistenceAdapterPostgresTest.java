package com.lasono.track.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.tuple;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.application.port.out.TrackPosition;
import com.lasono.track.application.port.out.TrackSummary;
import com.lasono.track.domain.model.TrackStatus;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.model.Visibility;

/**
 * The keyset query must give the same answers on a real PostgreSQL as the rules the use case
 * relies on: newest first, ties broken by id, strictly after the position, nothing skipped or
 * repeated.
 */
class TrackSummaryPersistenceAdapterPostgresTest extends PostgresIntegrationTest {

    private static final Instant START = Instant.parse("2026-10-04T10:00:00Z");

    @Autowired
    private TrackSummaryPersistenceAdapter adapter;

    @Test
    void returnsNothingWhenThereAreNoTracks() {
        assertThat(adapter.findNewestAfter(null, 10, null)).isEmpty();
    }

    @Test
    void mapsTheStoredColumnsToTheSummary() {
        UUID id = UUID.randomUUID();
        insert(id, "My song", "Some description", START);

        TrackSummary summary = adapter.findNewestAfter(null, 10, null).get(0);

        assertThat(summary).isEqualTo(new TrackSummary(id, TrackFixtures.OWNER.getValue(), "My song", "Some description", Visibility.PUBLIC, TrackStatus.PROCESSING, START, null));
    }

    @Test
    void returnsTheNewestTrackFirst() {
        insert(UUID.randomUUID(), "oldest", START);
        insert(UUID.randomUUID(), "newest", START.plusSeconds(2));
        insert(UUID.randomUUID(), "middle", START.plusSeconds(1));

        assertThat(titles(adapter.findNewestAfter(null, 10, null))).containsExactly("newest", "middle", "oldest");
    }

    @Test
    void respectsTheLimit() {
        for (int i = 0; i < 5; i++) {
            insert(UUID.randomUUID(), "track " + i, START.plusSeconds(i));
        }

        assertThat(adapter.findNewestAfter(null, 2, null)).hasSize(2);
    }

    @Test
    void ordersTracksCreatedAtTheSameTimeByIdDescendingComparingTheBytesUnsigned() {
        // Java's UUID.compareTo would put 8000... and ffff... before 7fff... (it compares signed).
        insert(id("00000000-0000-0000-0000-000000000001"), "lowest", START);
        insert(id("7fffffff-ffff-ffff-ffff-ffffffffffff"), "just below the sign bit", START);
        insert(id("80000000-0000-0000-0000-000000000000"), "just above the sign bit", START);
        insert(id("ffffffff-ffff-ffff-ffff-ffffffffffff"), "highest", START);

        assertThat(titles(adapter.findNewestAfter(null, 10, null)))
            .containsExactly("highest", "just above the sign bit", "just below the sign bit", "lowest");
    }

    @Test
    void startsStrictlyAfterThePosition() {
        UUID newest = UUID.randomUUID();
        UUID middle = UUID.randomUUID();
        insert(newest, "newest", START.plusSeconds(2));
        insert(middle, "middle", START.plusSeconds(1));
        insert(UUID.randomUUID(), "oldest", START);

        List<TrackSummary> page = adapter.findNewestAfter(new TrackPosition(START.plusSeconds(1), middle), 10, null);

        assertThat(titles(page)).containsExactly("oldest");
    }

    @Test
    void continuesInsideAGroupOfTracksCreatedAtTheSameTime() {
        insert(id("40000000-0000-0000-0000-000000000000"), "d", START);
        insert(id("30000000-0000-0000-0000-000000000000"), "c", START);
        insert(id("20000000-0000-0000-0000-000000000000"), "b", START);
        insert(id("10000000-0000-0000-0000-000000000000"), "a", START);
        insert(UUID.randomUUID(), "older", START.minusSeconds(1));

        List<TrackSummary> page =
            adapter.findNewestAfter(new TrackPosition(START, id("30000000-0000-0000-0000-000000000000")), 10, null);

        assertThat(titles(page)).containsExactly("b", "a", "older");
    }

    @Test
    void keepsMicrosecondPrecisionSoTheLastTrackOfAPageIsNotReturnedAgain() {
        Instant withMicros = Instant.parse("2026-10-04T10:00:00.123456Z");
        insert(UUID.randomUUID(), "precise", withMicros);

        TrackSummary summary = adapter.findNewestAfter(null, 10, null).get(0);
        List<TrackSummary> next = adapter.findNewestAfter(new TrackPosition(summary.createdAt(), summary.id()), 10, null);

        assertThat(summary.createdAt()).isEqualTo(withMicros);
        assertThat(next).isEmpty();
    }

    @Test
    void walkingPageByPageVisitsEveryTrackOnceInTheOrderThePostgresSorts() {
        // Pairs of tracks share a creation time, so only the id can order them.
        for (int i = 0; i < 11; i++) {
            insert(UUID.randomUUID(), "track " + i, START.plusSeconds(i / 2));
        }
        List<UUID> expected = jdbcTemplate.queryForList(
            "SELECT id FROM tracks ORDER BY created_at DESC, id DESC", UUID.class);

        List<UUID> visited = new ArrayList<>();
        TrackPosition position = null;
        List<TrackSummary> page;
        do {
            page = adapter.findNewestAfter(position, 3, null);
            page.forEach(summary -> visited.add(summary.id()));
            if (!page.isEmpty()) {
                TrackSummary last = page.get(page.size() - 1);
                position = new TrackPosition(last.createdAt(), last.id());
            }
        } while (page.size() == 3);

        assertThat(visited).containsExactlyElementsOf(expected);
    }

    @Test
    void readsTheDurationOfAProcessedTrack() {
        UUID id = UUID.randomUUID();
        insert(id, "My song", START);
        insertAudio(id, 3500L);

        assertThat(adapter.findNewestAfter(null, 10, null).get(0).durationMs()).isEqualTo(3500L);
    }

    @Test
    void hasNoDurationWhenTheAudioIsNotProcessedYetOrThereIsNoAudioRow() {
        UUID uploaded = UUID.randomUUID();
        UUID withoutAudio = UUID.randomUUID();
        insert(uploaded, "uploaded", START);
        insertAudio(uploaded, null);
        insert(withoutAudio, "no audio row", START.plusSeconds(1));

        assertThat(adapter.findNewestAfter(null, 10, null))
            .extracting(TrackSummary::durationMs)
            .containsExactly(null, null);
    }

    @Test
    void givesEachTrackItsOwnDuration() {
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        UUID third = UUID.randomUUID();
        insert(first, "first", START);
        insert(second, "second", START.plusSeconds(1));
        insert(third, "third", START.plusSeconds(2));
        insertAudio(first, 1000L);
        insertAudio(third, 3000L);

        assertThat(adapter.findNewestAfter(null, 10, null))
            .extracting(TrackSummary::title, TrackSummary::durationMs)
            .containsExactly(tuple("third", 3000L), tuple("second", null), tuple("first", 1000L));
    }

    private void insertAudio(UUID trackId, Long durationMs) {
        jdbcTemplate.update(
            "INSERT INTO audio_resources (id, track_id, status, duration_ms) VALUES (?, ?, 'READY', ?)",
            UUID.randomUUID(), trackId, durationMs);
    }

    private void insert(UUID id, String title, Instant createdAt) {
        insert(id, title, null, createdAt);
    }

    private static final UUID ALICE = UUID.fromString("00000000-0000-0000-0000-0000000000a1");
    private static final UUID BOB = UUID.fromString("00000000-0000-0000-0000-0000000000b2");

    private void insertFor(UUID owner, Visibility visibility, String title, Instant createdAt) {
        jdbcTemplate.update(
            "INSERT INTO tracks (id, owner_id, title, description, visibility, status, created_at) "
                + "VALUES (?, ?, ?, '', ?, 'READY', ?)",
            UUID.randomUUID(), owner, title, visibility.name(), OffsetDateTime.ofInstant(createdAt, ZoneOffset.UTC));
    }

    private void insert(UUID id, String title, String description, Instant createdAt) {
        jdbcTemplate.update(
            "INSERT INTO tracks (id, owner_id, title, description, visibility, status, created_at) "
                + "VALUES (?, ?, ?, ?, 'PUBLIC', 'PROCESSING', ?)",
            id, TrackFixtures.OWNER.getValue(), title, description, OffsetDateTime.ofInstant(createdAt, ZoneOffset.UTC));
    }

    private static UUID id(String value) {
        return UUID.fromString(value);
    }

    private static List<String> titles(List<TrackSummary> summaries) {
        return summaries.stream().map(TrackSummary::title).toList();
    }

    @Test
    void listsOnlyPublicTracksWhenNobodyIsLoggedIn() {
        insertFor(ALICE, Visibility.PUBLIC, "alice public", START.plusSeconds(2));
        insertFor(ALICE, Visibility.PRIVATE, "alice private", START.plusSeconds(1));
        insertFor(BOB, Visibility.PRIVATE, "bob private", START);

        assertThat(titles(adapter.findNewestAfter(null, 10, null))).containsExactly("alice public");
    }

    @Test
    void listsPublicTracksAndTheViewersOwnPrivateTracksButNotOthers() {
        insertFor(ALICE, Visibility.PUBLIC, "alice public", START.plusSeconds(3));
        insertFor(ALICE, Visibility.PRIVATE, "alice private", START.plusSeconds(2));
        insertFor(BOB, Visibility.PRIVATE, "bob private", START.plusSeconds(1));
        insertFor(BOB, Visibility.PUBLIC, "bob public", START);

        assertThat(titles(adapter.findNewestAfter(null, 10, ALICE)))
            .containsExactly("alice public", "alice private", "bob public");
        assertThat(titles(adapter.findNewestAfter(null, 10, BOB)))
            .containsExactly("alice public", "bob private", "bob public");
    }

    @Test
    void mapsTheOwnerAndTheVisibilityToTheSummary() {
        insertFor(ALICE, Visibility.PRIVATE, "alice private", START);

        TrackSummary summary = adapter.findNewestAfter(null, 10, ALICE).get(0);

        assertThat(summary.ownerId()).isEqualTo(ALICE);
        assertThat(summary.visibility()).isEqualTo(Visibility.PRIVATE);
    }

    // The filter is part of the query. If it were applied after the page was cut, a page could come back short
    // or empty while more tracks exist, and a reader would stop too early.
    @Test
    void pagesAreFullAndNothingIsSkippedWhenOtherPeoplesPrivateTracksSitBetween() {
        for (int i = 0; i < 6; i++) {
            insertFor(BOB, Visibility.PRIVATE, "bob private " + i, START.plusSeconds(20 - 2 * i));
            insertFor(ALICE, Visibility.PUBLIC, "alice public " + i, START.plusSeconds(19 - 2 * i));
        }

        List<TrackSummary> first = adapter.findNewestAfter(null, 4, null);
        TrackSummary last = first.get(first.size() - 1);
        List<TrackSummary> second = adapter.findNewestAfter(new TrackPosition(last.createdAt(), last.id()), 4, null);

        assertThat(titles(first)).containsExactly("alice public 0", "alice public 1", "alice public 2", "alice public 3");
        assertThat(titles(second)).containsExactly("alice public 4", "alice public 5");
    }
}
