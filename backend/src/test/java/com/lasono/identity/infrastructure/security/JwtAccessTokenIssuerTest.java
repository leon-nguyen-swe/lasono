package com.lasono.identity.infrastructure.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;

import com.lasono.config.JwtConfig;
import com.lasono.identity.application.port.out.IssuedAccessToken;
import com.lasono.identity.domain.UserId;

class JwtAccessTokenIssuerTest {

    private static final String SECRET = "a-secret-with-at-least-32-bytes-in-it!!";
    private static final String OTHER_SECRET = "another-secret-with-at-least-32-bytes!";

    // Fixed at "now" so the exact times can be compared, and the token is still valid for the decoder.
    private final Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS);
    private final Clock clock = Clock.fixed(now, ZoneOffset.UTC);
    private final JwtConfig config = new JwtConfig();
    private final JwtDecoder decoder = config.jwtDecoder(SECRET);
    private final JwtAccessTokenIssuer issuer =
        new JwtAccessTokenIssuer(config.jwtEncoder(SECRET), clock, Duration.ofMinutes(15));
    private final UserId userId = new UserId(UUID.randomUUID());

    @Test
    void issue_shouldSayWhichUserTheTokenIsFor() {
        Jwt jwt = decoder.decode(issuer.issue(userId).value());

        assertThat(jwt.getSubject()).isEqualTo(userId.getValue().toString());
        assertThat(jwt.getClaimAsString("iss")).isEqualTo("lasono");
    }

    @Test
    void issue_shouldLastFor15Minutes() {
        IssuedAccessToken token = issuer.issue(userId);

        Jwt jwt = decoder.decode(token.value());
        assertThat(jwt.getIssuedAt()).isEqualTo(now);
        assertThat(jwt.getExpiresAt()).isEqualTo(now.plus(15, ChronoUnit.MINUTES));
        assertThat(token.expiresInSeconds()).isEqualTo(900);
    }

    @Test
    void issue_shouldFollowTheConfiguredLifetime() {
        JwtAccessTokenIssuer shortLived =
            new JwtAccessTokenIssuer(config.jwtEncoder(SECRET), clock, Duration.ofMinutes(5));

        IssuedAccessToken token = shortLived.issue(userId);

        assertThat(decoder.decode(token.value()).getExpiresAt()).isEqualTo(now.plus(5, ChronoUnit.MINUTES));
        assertThat(token.expiresInSeconds()).isEqualTo(300);
    }

    @Test
    void issue_shouldSignWithHs256() {
        Jwt jwt = decoder.decode(issuer.issue(userId).value());

        assertThat(jwt.getHeaders().get("alg")).isEqualTo("HS256");
    }

    // A token is signed, not encrypted: anyone holding it can read it, so it carries no personal data.
    @Test
    void issue_shouldCarryNothingButIssuerSubjectAndTimes() {
        Jwt jwt = decoder.decode(issuer.issue(userId).value());

        assertThat(jwt.getClaims().keySet()).containsExactlyInAnyOrder("iss", "sub", "iat", "exp");
    }

    @Test
    void issue_shouldProduceATokenThatAnotherSecretRefuses() {
        String token = issuer.issue(userId).value();

        assertThatThrownBy(() -> config.jwtDecoder(OTHER_SECRET).decode(token)).isInstanceOf(JwtException.class);
    }
}
