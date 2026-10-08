package com.lasono.identity.application.usecase;

import java.time.Clock;
import java.time.Instant;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.lasono.identity.application.port.out.RefreshTokenCodec;
import com.lasono.identity.domain.RefreshTokenRepository;

@Component
public class LogoutUseCase {

    private final RefreshTokenRepository refreshTokenRepository;
    private final RefreshTokenCodec refreshTokenCodec;
    private final Clock clock;

    public LogoutUseCase(RefreshTokenRepository refreshTokenRepository, RefreshTokenCodec refreshTokenCodec, Clock clock) {
        this.refreshTokenRepository = refreshTokenRepository;
        this.refreshTokenCodec = refreshTokenCodec;
        this.clock = clock;
    }

    /**
     * Ends the session the token belongs to. A token that is missing or unknown is not an error: there is
     * nothing to end, which is what the caller wanted.
     */
    @Transactional
    public void execute(String rawRefreshToken) {
        if (rawRefreshToken == null || rawRefreshToken.isBlank()) {
            return;
        }
        Instant now = clock.instant();
        refreshTokenRepository
            .findByTokenHashForUpdate(refreshTokenCodec.hash(rawRefreshToken))
            .ifPresent(token -> refreshTokenRepository.revokeFamily(token.getFamilyId(), now));
    }
}
