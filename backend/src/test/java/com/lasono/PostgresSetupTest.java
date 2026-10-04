package com.lasono;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class PostgresSetupTest extends PostgresIntegrationTest {

    @Test
    void runsAgainstARealPostgresTestDatabase() {
        String database = jdbcTemplate.queryForObject("SELECT current_database()", String.class);
        String version = jdbcTemplate.queryForObject("SELECT version()", String.class);

        assertThat(database).isEqualTo("lasono_test");
        assertThat(version).startsWith("PostgreSQL");
    }

    @Test
    void flywayHasAppliedTheMigrations() {
        Integer applied = jdbcTemplate.queryForObject(
            "SELECT count(*) FROM flyway_schema_history WHERE success", Integer.class);

        assertThat(applied).isGreaterThanOrEqualTo(1);
    }
}
