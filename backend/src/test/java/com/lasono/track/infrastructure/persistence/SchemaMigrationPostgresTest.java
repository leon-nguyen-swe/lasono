package com.lasono.track.infrastructure.persistence;

import javax.sql.DataSource;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;

import com.lasono.PostgresIntegrationTest;

/**
 * A migration runs once on a database that already holds data and cannot be undone, so it is tried on data
 * from before it existed: the database is built up to an older version, rows are added, then it is migrated.
 * It all happens in its own schema, so the real tables are never touched.
 */
abstract class SchemaMigrationPostgresTest extends PostgresIntegrationTest {

    protected static final String SCHEMA = "migration_test";

    @Autowired
    private DataSource dataSource;

    @BeforeEach
    @AfterEach
    void dropTheScratchSchema() {
        jdbcTemplate.execute("DROP SCHEMA IF EXISTS " + SCHEMA + " CASCADE");
    }

    /** Migrates the scratch schema up to the given version, or to the newest one for {@code "latest"}. */
    protected Flyway flyway(String target) {
        return Flyway.configure()
            .dataSource(dataSource)
            .schemas(SCHEMA)
            .defaultSchema(SCHEMA)
            .locations("classpath:db/migration")
            .target(target)
            .load();
    }
}
