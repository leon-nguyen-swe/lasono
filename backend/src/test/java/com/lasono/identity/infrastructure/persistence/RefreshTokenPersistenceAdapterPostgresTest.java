package com.lasono.identity.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.support.TransactionTemplate;

import com.lasono.PostgresIntegrationTest;
import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.RefreshToken;
import com.lasono.identity.domain.RefreshTokenCheck;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;

/**
 * Two requests that exchange the same refresh token at the same moment must not both succeed, so the lock on
 * the row and the revoking of a whole family have to work on a real PostgreSQL, not only in memory.
 */
class RefreshTokenPersistenceAdapterPostgresTest extends PostgresIntegrationTest {

    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final Duration LIFETIME = Duration.ofDays(30);

    @Autowired
    private RefreshTokenPersistenceAdapter adapter;

    @Autowired
    private UserPersistenceAdapter users;

    @Autowired
    private TransactionTemplate transactionTemplate;

    private UserId alice;

    // A refresh token belongs to a user (foreign key), so the user must exist first.
    @BeforeEach
    void createUser() {
        alice = new UserId(UUID.randomUUID());
        users.save(new User(alice, new Email("alice@example.com"), new DisplayName("Alice"), "$2a$10$hash"));
    }

    private RefreshToken aToken(String hash) {
        return RefreshToken.issueNewFamily(alice, hash, NOW, LIFETIME);
    }

    private RefreshToken find(String hash) {
        return transactionTemplate.execute(status -> adapter.findByTokenHashForUpdate(hash).orElseThrow());
    }

    @Test
    void aSavedTokenComesBackWithAllItsData() {
        RefreshToken token = aToken("hash-1");
        adapter.save(token);

        RefreshToken found = find("hash-1");

        assertThat(found.getId()).isEqualTo(token.getId());
        assertThat(found.getFamilyId()).isEqualTo(token.getFamilyId());
        assertThat(found.getUserId()).isEqualTo(alice);
        assertThat(found.getTokenHash()).isEqualTo("hash-1");
        assertThat(found.getExpiresAt()).isEqualTo(NOW.plus(LIFETIME));
        assertThat(found.getUsedAt()).isNull();
        assertThat(found.getRevokedAt()).isNull();
    }

    @Test
    void aHashThatWasNeverSavedGivesNothing() {
        adapter.save(aToken("hash-1"));

        Optional<RefreshToken> found = transactionTemplate.execute(status -> adapter.findByTokenHashForUpdate("other"));

        assertThat(found).isEmpty();
    }

    @Test
    void savingAgainStoresWhenTheTokenWasUsedAndRevoked() {
        RefreshToken token = aToken("hash-1");
        adapter.save(token);
        token.markUsed(NOW.plusSeconds(5));
        token.revoke(NOW.plusSeconds(6));

        adapter.save(token);

        RefreshToken found = find("hash-1");
        assertThat(found.getUsedAt()).isEqualTo(NOW.plusSeconds(5));
        assertThat(found.getRevokedAt()).isEqualTo(NOW.plusSeconds(6));
        assertThat(found.check(NOW.plusSeconds(7))).isEqualTo(RefreshTokenCheck.REVOKED);
    }

    @Test
    void revokingAFamilyRevokesAllItsTokensAndNoOther() {
        RefreshToken first = aToken("hash-1");
        RefreshToken second = RefreshToken.issueInFamily(first.getFamilyId(), alice, "hash-2", NOW, LIFETIME);
        RefreshToken stranger = aToken("hash-3");
        adapter.save(first);
        adapter.save(second);
        adapter.save(stranger);

        transactionTemplate.executeWithoutResult(status -> adapter.revokeFamily(first.getFamilyId(), NOW.plusSeconds(9)));

        assertThat(find("hash-1").getRevokedAt()).isEqualTo(NOW.plusSeconds(9));
        assertThat(find("hash-2").getRevokedAt()).isEqualTo(NOW.plusSeconds(9));
        assertThat(find("hash-3").getRevokedAt()).isNull();
    }

    @Test
    void revokingAFamilyKeepsAnEarlierRevocationMoment() {
        RefreshToken token = aToken("hash-1");
        token.revoke(NOW.plusSeconds(1));
        adapter.save(token);

        transactionTemplate.executeWithoutResult(status -> adapter.revokeFamily(token.getFamilyId(), NOW.plusSeconds(60)));

        assertThat(find("hash-1").getRevokedAt()).isEqualTo(NOW.plusSeconds(1));
    }

    @Test
    void twoTokensCannotShareTheSameHash() {
        adapter.save(aToken("hash-1"));

        assertThatThrownBy(() -> adapter.save(aToken("hash-1"))).isInstanceOf(DataIntegrityViolationException.class);

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM refresh_tokens", Integer.class)).isEqualTo(1);
    }

    @Test
    void deletingTheUserDeletesItsTokens() {
        adapter.save(aToken("hash-1"));
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM refresh_tokens", Integer.class)).isEqualTo(1);

        jdbcTemplate.update("DELETE FROM users WHERE id = ?", alice.getValue());

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM refresh_tokens", Integer.class)).isZero();
    }

    // The point of the lock: the second exchange has to wait for the first and then see the token as used,
    // not read it as unused at the same time and hand out a second new token.
    @Test
    void aSecondExchangeOfTheSameTokenWaitsForTheFirstAndThenSeesItAsUsed() throws Exception {
        adapter.save(aToken("hash-1"));
        ExecutorService executor = Executors.newFixedThreadPool(1);
        CountDownLatch firstHoldsTheLock = new CountDownLatch(1);
        try {
            Future<?> first = executor.submit(() -> transactionTemplate.executeWithoutResult(status -> {
                RefreshToken locked = adapter.findByTokenHashForUpdate("hash-1").orElseThrow();
                firstHoldsTheLock.countDown();
                pause(700);
                locked.markUsed(NOW.plusSeconds(1));
                adapter.save(locked);
            }));
            // A wait with a limit: if the first exchange fails before it holds the lock, the test must fail
            // and not wait for ever.
            assertThat(firstHoldsTheLock.await(5, TimeUnit.SECONDS)).as("the first exchange holds the lock").isTrue();

            long startedWaiting = System.nanoTime();
            RefreshTokenCheck seenBySecond = transactionTemplate.execute(status ->
                adapter.findByTokenHashForUpdate("hash-1").orElseThrow().check(NOW.plusSeconds(2)));
            long waitedMillis = (System.nanoTime() - startedWaiting) / 1_000_000;
            first.get(10, TimeUnit.SECONDS);

            assertThat(seenBySecond).isEqualTo(RefreshTokenCheck.ALREADY_USED);
            assertThat(waitedMillis).isGreaterThan(300);
        } finally {
            executor.shutdownNow();
        }
    }

    private static void pause(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
