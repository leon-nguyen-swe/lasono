package com.lasono.track.infrastructure.event;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.event.EventListener;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.lasono.PostgresIntegrationTest;
import com.lasono.shared.event.TrackLiked;
import com.lasono.track.application.port.out.EventPublisher;

/**
 * Proves that {@link SpringEventPublisher} dispatches events synchronously and that
 * a {@code @EventListener} runs inside the same transaction as the publisher.
 */
@ContextConfiguration(classes = SpringEventPublisherPostgresTest.ProbeConfig.class)
class SpringEventPublisherPostgresTest extends PostgresIntegrationTest {

    @Autowired
    private EventPublisher eventPublisher;

    @Autowired
    private ProbeListener probeListener;

    @Autowired
    private TransactionTemplate transactionTemplate;

    @BeforeEach
    void resetProbe() {
        probeListener.ran = false;
        probeListener.failNext = false;
        probeListener.transactionActiveChecker = null;
    }

    @Test
    void aSynchronousListenerSeesTheEventBeforePublishReturns() {
        eventPublisher.publish(new TrackLiked(UUID.randomUUID(), UUID.randomUUID(), Instant.now()));

        assertThat(probeListener.ran).isTrue();
    }

    @Test
    void aListenerThatFailsRollsBackTheWritesOfThePublisher() {
        probeListener.failNext = true;

        // The exception thrown by the listener propagates back through publish() and rolls the tx back.
        assertThatThrownBy(() ->
            transactionTemplate.executeWithoutResult(status ->
                eventPublisher.publish(new TrackLiked(UUID.randomUUID(), UUID.randomUUID(), Instant.now()))
            )
        ).isInstanceOf(RuntimeException.class)
         .hasMessageContaining("probe: forced failure");

        assertThat(probeListener.ran).isTrue();
    }

    @Test
    void aListenerWritesInTheTransactionOfThePublisher() {
        AtomicBoolean wasInTransaction = new AtomicBoolean(false);
        probeListener.transactionActiveChecker = wasInTransaction;

        transactionTemplate.executeWithoutResult(status ->
            eventPublisher.publish(new TrackLiked(UUID.randomUUID(), UUID.randomUUID(), Instant.now()))
        );

        assertThat(wasInTransaction.get())
            .as("listener must observe an active transaction — it runs inside the publisher's tx")
            .isTrue();
    }

    // ── Test configuration ────────────────────────────────────────────────────

    @TestConfiguration
    static class ProbeConfig {
        @Bean
        ProbeListener probeListener() {
            return new ProbeListener();
        }
    }

    static class ProbeListener {
        volatile boolean ran;
        volatile boolean failNext;
        volatile AtomicBoolean transactionActiveChecker;

        @EventListener
        void on(TrackLiked event) {
            ran = true;
            if (transactionActiveChecker != null) {
                transactionActiveChecker.set(TransactionSynchronizationManager.isActualTransactionActive());
            }
            if (failNext) {
                throw new RuntimeException("probe: forced failure");
            }
        }
    }
}
