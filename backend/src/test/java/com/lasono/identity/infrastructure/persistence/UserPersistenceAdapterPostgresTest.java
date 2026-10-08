package com.lasono.identity.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;

import com.lasono.PostgresIntegrationTest;
import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;
import com.lasono.identity.domain.exception.EmailAlreadyRegisteredException;

/**
 * The rules "an email belongs to one account" and "a password is stored only as a hash" have to hold
 * on a real PostgreSQL, because the unique constraint is what decides a race between two sign-ups.
 */
class UserPersistenceAdapterPostgresTest extends PostgresIntegrationTest {

    @Autowired
    private UserPersistenceAdapter adapter;

    @Test
    void savingAUserStoresItsColumns() {
        User alice = aUser("alice@example.com", "Alice");
        Instant before = Instant.now().truncatedTo(ChronoUnit.MICROS);

        adapter.save(alice);

        Instant after = Instant.now();
        List<Map<String, Object>> rows = jdbcTemplate.queryForList("SELECT * FROM users");
        assertThat(rows).hasSize(1);
        Map<String, Object> row = rows.get(0);
        assertThat(row.get("id")).isEqualTo(alice.getId().getValue());
        assertThat(row.get("email")).isEqualTo("alice@example.com");
        assertThat(row.get("display_name")).isEqualTo("Alice");
        assertThat(row.get("password_hash")).isEqualTo("$2a$10$hash");
        // queryForList gives a java.sql.Timestamp for this column, so read it as an OffsetDateTime directly.
        OffsetDateTime createdAt = jdbcTemplate.queryForObject("SELECT created_at FROM users", OffsetDateTime.class);
        assertThat(createdAt.toInstant()).isBetween(before, after);
    }

    @Test
    void aVietnameseDisplayNameIsStoredWithoutDamage() {
        adapter.save(aUser("an@example.com", "Nguyễn Văn Á"));

        String stored = jdbcTemplate.queryForObject("SELECT display_name FROM users", String.class);
        assertThat(stored).isEqualTo("Nguyễn Văn Á");
    }

    @Test
    void aSavedUserCanBeFoundByEmailWithAllItsData() {
        User alice = aUser("alice@example.com", "Nguyễn Văn Á");
        adapter.save(alice);

        User found = adapter.findByEmail(new Email("alice@example.com")).orElseThrow();

        assertThat(found.getId()).isEqualTo(alice.getId());
        assertThat(found.getEmail()).isEqualTo(alice.getEmail());
        assertThat(found.getDisplayName()).isEqualTo(alice.getDisplayName());
        assertThat(found.getPasswordHash()).isEqualTo("$2a$10$hash");
    }

    @Test
    void aSavedUserCanBeFoundById() {
        User alice = aUser("alice@example.com", "Alice");
        adapter.save(aUser("bob@example.com", "Bob"));
        adapter.save(alice);

        User found = adapter.findById(alice.getId()).orElseThrow();

        assertThat(found.getEmail()).isEqualTo(alice.getEmail());
        assertThat(found.getDisplayName()).isEqualTo(alice.getDisplayName());
    }

    @Test
    void anEmailOrIdThatWasNeverSavedGivesNothing() {
        adapter.save(aUser("alice@example.com", "Alice"));

        assertThat(adapter.findByEmail(new Email("nobody@example.com"))).isEmpty();
        assertThat(adapter.findById(new UserId(UUID.randomUUID()))).isEmpty();
    }

    @Test
    void aSecondUserWithTheSameEmailIsRejectedAndTheFirstStays() {
        adapter.save(aUser("alice@example.com", "Alice"));

        assertThatThrownBy(() -> adapter.save(aUser("alice@example.com", "Impostor")))
            .isInstanceOf(EmailAlreadyRegisteredException.class);

        assertThat(jdbcTemplate.queryForList("SELECT display_name FROM users", String.class))
            .containsExactly("Alice");
    }

    @Test
    void twoSignUpsWithTheSameEmailAtTheSameTimeLetExactlyOneWin() throws Exception {
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            List<Future<User>> attempts = List.of(
                executor.submit(() -> {
                    start.await();
                    return adapter.save(aUser("alice@example.com", "First"));
                }),
                executor.submit(() -> {
                    start.await();
                    return adapter.save(aUser("alice@example.com", "Second"));
                })
            );
            start.countDown();

            int saved = 0;
            int rejected = 0;
            for (Future<User> attempt : attempts) {
                try {
                    attempt.get(10, TimeUnit.SECONDS);
                    saved++;
                } catch (ExecutionException e) {
                    // Not a raw DataIntegrityViolationException: the caller must see the domain error.
                    assertThat(e.getCause()).isInstanceOf(EmailAlreadyRegisteredException.class);
                    rejected++;
                }
            }

            assertThat(saved).isEqualTo(1);
            assertThat(rejected).isEqualTo(1);
            assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM users", Integer.class)).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    // The adapter recognises a taken email by this constraint name, so the name is part of the contract.
    @Test
    void theEmailColumnHasAUniqueConstraintNamedUqUsersEmail() {
        List<String> uniqueConstraints = jdbcTemplate.queryForList(
            "SELECT conname FROM pg_constraint WHERE conrelid = 'users'::regclass AND contype = 'u'",
            String.class);

        assertThat(uniqueConstraints).containsExactly("uq_users_email");
    }

    @Test
    void theDatabaseRefusesAnEmailThatIsNotLowercase() {
        assertThatThrownBy(() -> jdbcTemplate.update(
            "INSERT INTO users (id, email, display_name, password_hash) VALUES (?, ?, ?, ?)",
            UUID.randomUUID(), "Alice@Example.com", "Alice", "$2a$10$hash"))
            .isInstanceOf(DataIntegrityViolationException.class);
    }

    private static User aUser(String email, String displayName) {
        return new User(new UserId(UUID.randomUUID()), new Email(email), new DisplayName(displayName), "$2a$10$hash");
    }
}
