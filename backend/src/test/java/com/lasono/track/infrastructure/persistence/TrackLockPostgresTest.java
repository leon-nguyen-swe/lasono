package com.lasono.track.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.support.TransactionTemplate;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;

/**
 * Two requests that change or delete the same track must take turns. Otherwise a change that read the track
 * before a delete would save its copy afterwards, and the deleted track would be back. Only a real PostgreSQL
 * shows that the row lock does this.
 */
class TrackLockPostgresTest extends PostgresIntegrationTest {

    @Autowired
    private TrackPersistenceAdapter adapter;

    @Autowired
    private TransactionTemplate transactionTemplate;

    @Test
    void aSecondRequestWaitsForTheFirstAndThenFindsTheTrackGone() throws Exception {
        TrackId id = new TrackId(UUID.randomUUID());
        adapter.save(new Track(id, TrackFixtures.OWNER, "Doomed", null));
        ExecutorService executor = Executors.newFixedThreadPool(1);
        CountDownLatch firstHoldsTheLock = new CountDownLatch(1);
        try {
            Future<?> deleter = executor.submit(() -> transactionTemplate.executeWithoutResult(status -> {
                adapter.findByIdForUpdate(id).orElseThrow();
                firstHoldsTheLock.countDown();
                pause(700);
                adapter.delete(id);
            }));
            // A wait with a limit: if the first request fails before it holds the lock, the test must fail
            // and not wait for ever.
            assertThat(firstHoldsTheLock.await(5, TimeUnit.SECONDS)).as("the first request holds the lock").isTrue();

            long startedWaiting = System.nanoTime();
            Optional<Track> seenBySecond = transactionTemplate.execute(status -> adapter.findByIdForUpdate(id));
            long waitedMillis = (System.nanoTime() - startedWaiting) / 1_000_000;
            deleter.get(10, TimeUnit.SECONDS);

            assertThat(seenBySecond).isEmpty();
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
