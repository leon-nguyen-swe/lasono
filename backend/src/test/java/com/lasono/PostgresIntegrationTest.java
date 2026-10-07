package com.lasono;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.SQLException;

import javax.sql.DataSource;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

/**
 * Base class for tests that need a real PostgreSQL instead of the in-memory H2 used by the other
 * tests. They run with {@code ./gradlew postgresTest} against the {@code lasono_test} database,
 * with Flyway migrations applied and Hibernate validating the schema.
 */
@Tag("postgres")
@SpringBootTest
@ActiveProfiles("postgres-test")
public abstract class PostgresIntegrationTest {

    private static final String TEST_DATABASE = "lasono_test";

    @Autowired
    protected JdbcTemplate jdbcTemplate;

    @Autowired
    private DataSource dataSource;

    /**
     * Empties the tables so every test starts from a clean database. The guard comes first so a
     * wrong connection setting can never delete the data of the development database.
     */
    @BeforeEach
    void cleanTestDatabase() throws SQLException {
        try (var connection = dataSource.getConnection()) {
            assertThat(connection.getCatalog())
                .as("Postgres tests must only run against the %s database", TEST_DATABASE)
                .isEqualTo(TEST_DATABASE);
        }

        jdbcTemplate.update("DELETE FROM processing_jobs");
        jdbcTemplate.update("DELETE FROM audio_resources");
        jdbcTemplate.update("DELETE FROM tracks");
        jdbcTemplate.update("DELETE FROM users");
    }
}
