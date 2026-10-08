package com.lasono.track.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;

import org.junit.jupiter.api.Test;

class TrackVisibilityMigrationPostgresTest extends SchemaMigrationPostgresTest {

    private static final UUID SOMEONE = UUID.fromString("00000000-0000-0000-0000-0000000000a1");

    private void insertTrack(UUID id, String visibility) {
        jdbcTemplate.update(
            "INSERT INTO " + SCHEMA + ".tracks (id, owner_id, title, description, status, visibility) "
                + "VALUES (?, ?, 'a song', NULL, 'READY', ?)",
            id, SOMEONE, visibility);
    }

    // The tracks of today were public before tracks could be private, and must stay in the list.
    @Test
    void tracksFromBeforeVisibilityStayPublic() {
        flyway("6").migrate();
        UUID id = UUID.randomUUID();
        jdbcTemplate.update(
            "INSERT INTO " + SCHEMA + ".tracks (id, owner_id, title, description, status) "
                + "VALUES (?, ?, 'old song', NULL, 'READY')",
            id, SOMEONE);

        flyway("latest").migrate();

        assertThat(jdbcTemplate.queryForObject(
            "SELECT visibility FROM " + SCHEMA + ".tracks WHERE id = ?", String.class, id)).isEqualTo("PUBLIC");
    }

    @Test
    void bothVisibilitiesAreAccepted() {
        flyway("latest").migrate();

        insertTrack(UUID.randomUUID(), "PUBLIC");
        insertTrack(UUID.randomUUID(), "PRIVATE");

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM " + SCHEMA + ".tracks", Integer.class))
            .isEqualTo(2);
    }

    // The code parses the value, but a direct INSERT or a future bug must not be able to store something else.
    @Test
    void theDatabaseRefusesAnyOtherVisibility() {
        flyway("latest").migrate();

        assertThatThrownBy(() -> insertTrack(UUID.randomUUID(), "SECRET")).hasMessageContaining("visibility");
    }

    // With a default, a forgotten value would quietly decide who can see a track. Without one, it is an error.
    @Test
    void aNewTrackMustSayWhoCanSeeIt() {
        flyway("latest").migrate();

        assertThatThrownBy(() -> jdbcTemplate.update(
            "INSERT INTO " + SCHEMA + ".tracks (id, owner_id, title, description, status) "
                + "VALUES (?, ?, 'a song', NULL, 'READY')",
            UUID.randomUUID(), SOMEONE)).hasMessageContaining("visibility");
    }
}
