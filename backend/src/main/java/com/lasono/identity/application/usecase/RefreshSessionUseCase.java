package com.lasono.identity.application.usecase;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.lasono.identity.application.port.out.AccessTokenIssuer;
import com.lasono.identity.application.port.out.IssuedAccessToken;
import com.lasono.identity.application.port.out.RefreshTokenCodec;
import com.lasono.identity.domain.RefreshToken;
import com.lasono.identity.domain.RefreshTokenCheck;
import com.lasono.identity.domain.RefreshTokenRepository;

@Component
public class RefreshSessionUseCase {

    private static final String TOKEN_TYPE = "Bearer";

    private final RefreshTokenRepository refreshTokenRepository;
    private final RefreshTokenCodec refreshTokenCodec;
    private final AccessTokenIssuer accessTokenIssuer;
    private final Clock clock;
    private final Duration refreshTokenTtl;

    public RefreshSessionUseCase(
        RefreshTokenRepository refreshTokenRepository,
        RefreshTokenCodec refreshTokenCodec,
        AccessTokenIssuer accessTokenIssuer,
        Clock clock,
        @Value("${lasono.jwt.refresh-token-ttl:30d}") Duration refreshTokenTtl
    ) {
        this.refreshTokenRepository = refreshTokenRepository;
        this.refreshTokenCodec = refreshTokenCodec;
        this.accessTokenIssuer = accessTokenIssuer;
        this.clock = clock;
        this.refreshTokenTtl = refreshTokenTtl;
    }

    // One transaction around the whole exchange keeps the row of the token locked from the read to the end,
    // so two requests with the same token cannot both succeed.
    //
    // noRollbackFor matters: when a used token is shown again, the whole family is revoked and then this
    // exception is thrown. By default a RuntimeException rolls the transaction back, which would undo the
    // revoking and leave a stolen family alive while the caller only sees a "401".
    @Transactional(noRollbackFor = InvalidRefreshTokenException.class)
    public AuthSession execute(String rawRefreshToken) {
        if (rawRefreshToken == null || rawRefreshToken.isBlank()) {
            throw new InvalidRefreshTokenException();
        }
        Instant now = clock.instant();

        RefreshToken token = refreshTokenRepository
            .findByTokenHashForUpdate(refreshTokenCodec.hash(rawRefreshToken))
            .orElseThrow(InvalidRefreshTokenException::new);

        RefreshTokenCheck state = token.check(now);
        if (state == RefreshTokenCheck.ALREADY_USED) {
            refreshTokenRepository.revokeFamily(token.getFamilyId(), now);
        }
        if (state != RefreshTokenCheck.USABLE) {
            throw new InvalidRefreshTokenException();
        }

        token.markUsed(now);
        refreshTokenRepository.save(token);

        String newRawToken = refreshTokenCodec.generate();
        refreshTokenRepository.save(RefreshToken.issueInFamily(
            token.getFamilyId(),
            token.getUserId(),
            refreshTokenCodec.hash(newRawToken),
            now,
            refreshTokenTtl
        ));

        IssuedAccessToken access = accessTokenIssuer.issue(token.getUserId());
        return new AuthSession(new LoginResult(access.value(), TOKEN_TYPE, access.expiresInSeconds()), newRawToken);
    }
}
