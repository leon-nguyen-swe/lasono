package com.lasono.identity.infrastructure.security;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Component;

import com.lasono.config.JwtConfig;
import com.lasono.identity.application.port.out.AccessTokenIssuer;
import com.lasono.identity.application.port.out.IssuedAccessToken;
import com.lasono.identity.domain.UserId;

@Component
public class JwtAccessTokenIssuer implements AccessTokenIssuer {

    private final JwtEncoder encoder;
    private final Clock clock;
    private final Duration timeToLive;

    public JwtAccessTokenIssuer(
        JwtEncoder encoder,
        Clock clock,
        @Value("${lasono.jwt.access-token-ttl:15m}") Duration timeToLive
    ) {
        this.encoder = encoder;
        this.clock = clock;
        this.timeToLive = timeToLive;
    }

    @Override
    public IssuedAccessToken issue(UserId userId) {
        Instant issuedAt = clock.instant();

        // Only who issued it, who it is for and when. A JWT is signed, not encrypted, so anyone can read it.
        JwtClaimsSet claims = JwtClaimsSet.builder()
            .issuer(JwtConfig.ISSUER)
            .subject(userId.getValue().toString())
            .issuedAt(issuedAt)
            .expiresAt(issuedAt.plus(timeToLive))
            .build();

        String token = encoder
            .encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims))
            .getTokenValue();

        return new IssuedAccessToken(token, timeToLive.toSeconds());
    }
}
