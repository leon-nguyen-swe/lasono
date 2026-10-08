package com.lasono.track.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import javax.sql.DataSource;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.lasono.PostgresIntegrationTest;
import com.lasono.identity.infrastructure.security.BCryptPasswordHasher;

/**
 * The migration that gives tracks an owner runs once on a database that already holds tracks, and it cannot be
 * undone. So it is tried here on data from before it existed: the database is built up to V5, old tracks are
 * added, then the migration runs. It all happens in its own schema, so the real tables are never touched.
 */
class TrackOwnerMigrationPostgresTest extends PostgresIntegrationTest {

    private static final String SCHEMA = "migration_test";
    private static final UUID LEGACY_USER = UUID.fromString("00000000-0000-0000-0000-00000000001e");

    @Autowired
    private DataSource dataSource;

    @BeforeEach
    @AfterEach
    void dropTheScratchSchema() {
        jdbcTemplate.execute("DROP SCHEMA IF EXISTS " + SCHEMA + " CASCADE");
    }

    private Flyway flyway(String target) {
        return Flyway.configure()
            .dataSource(dataSource)
            .schemas(SCHEMA)
            .defaultSchema(SCHEMA)
            .locations("classpath:db/migration")
            .target(target)
            .load();
    }

    private void insertOldTrack(UUID id, String title) {
        jdbcTemplate.update(
            "INSERT INTO " + SCHEMA + ".tracks (id, title, description, status) VALUES (?, ?, NULL, 'READY')",
            id, title);
    }

    @Test
    void tracksFromBeforeAccountsBelongToTheLegacyUser() {
        flyway("5").migrate();
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        insertOldTrack(first, "Old song 1");
        insertOldTrack(second, "Old song 2");

        flyway("latest").migrate();

        List<Map<String, Object>> tracks = jdbcTemplate.queryForList(
            "SELECT id, title, owner_id FROM " + SCHEMA + ".tracks ORDER BY title");
        assertThat(tracks).hasSize(2);
        assertThat(tracks).allSatisfy(track -> assertThat(track.get("owner_id")).isEqualTo(LEGACY_USER));
        assertThat(tracks.get(0).get("id")).isEqualTo(first);
        assertThat(jdbcTemplate.queryForObject(
            "SELECT count(*) FROM " + SCHEMA + ".users WHERE id = ?", Integer.class, LEGACY_USER)).isEqualTo(1);
    }

    // Anyone could otherwise try to log in as the owner of all the old tracks.
    @Test
    void theLegacyUserCannotLogInWithAnyPassword() {
        flyway("5").migrate();
        insertOldTrack(UUID.randomUUID(), "Old song");

        flyway("latest").migrate();

        String hash = jdbcTemplate.queryForObject(
            "SELECT password_hash FROM " + SCHEMA + ".users WHERE id = ?", String.class, LEGACY_USER);
        BCryptPasswordHasher hasher = new BCryptPasswordHasher();
        assertThat(hasher.matches("", hash)).isFalse();
        assertThat(hasher.matches("!", hash)).isFalse();
        assertThat(hasher.matches("password", hash)).isFalse();
    }

    @Test
    void aDatabaseWithoutTracksGetsNoLegacyUser() {
        flyway("latest").migrate();

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM " + SCHEMA + ".users", Integer.class)).isZero();
    }

    @Test
    void everyNewTrackMustHaveAnOwner() {
        flyway("latest").migrate();

        assertThatThrownBy(() -> insertOldTrack(UUID.randomUUID(), "No owner"))
            .hasMessageContaining("owner_id");
    }

    // D6: modules hold each other's ids as plain values, so the database has no link either.
    @Test
    void theOwnerColumnHasNoForeignKeyToUsers() {
        flyway("latest").migrate();

        Integer foreignKeys = jdbcTemplate.queryForObject(
            "SELECT count(*) FROM information_schema.table_constraints "
                + "WHERE constraint_type = 'FOREIGN KEY' AND table_schema = ? AND table_name = 'tracks'",
            Integer.class, SCHEMA);
        assertThat(foreignKeys).isZero();
    }
}
