package com.lasono.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.JwtException;

/**
 * A token is only worth something if the server refuses every token it did not sign itself.
 * These tests try the classic forgeries against the decoder.
 */
class JwtConfigTest {

    private static final String SECRET = "a-secret-with-at-least-32-bytes-in-it!!";
    private static final String OTHER_SECRET = "another-secret-with-at-least-32-bytes!";

    private final JwtConfig config = new JwtConfig();
    private final JwtEncoder encoder = config.jwtEncoder(SECRET);
    private final JwtDecoder decoder = config.jwtDecoder(SECRET);

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"short", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"})
    void signingKey_shouldRefuseASecretShorterThan32Bytes(String secret) {
        assertThatThrownBy(() -> JwtConfig.signingKey(secret))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("LASONO_JWT_SECRET");
    }

    @Test
    void signingKey_shouldAcceptExactly32Bytes() {
        assertThatCode(() -> JwtConfig.signingKey("x".repeat(32))).doesNotThrowAnyException();
    }

    // 10 x "ế" is 10 characters but 30 bytes; 11 of them are 33 bytes.
    @Test
    void signingKey_shouldCountBytesAndNotCharacters() {
        assertThatThrownBy(() -> JwtConfig.signingKey("ế".repeat(10))).isInstanceOf(IllegalStateException.class);
        assertThatCode(() -> JwtConfig.signingKey("ế".repeat(11))).doesNotThrowAnyException();
    }

    // The beans must go through the same check, or the application would start with a weak secret.
    @Test
    void encoderAndDecoder_shouldRefuseToBeCreatedWithAWeakSecret() {
        assertThatThrownBy(() -> config.jwtEncoder("short")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> config.jwtDecoder("")).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void decoder_shouldAcceptATokenItSignedWithTheRightClaims() {
        String token = sign(encoder, claims("lasono", minutesFromNow(-1), minutesFromNow(10)));

        assertThat(decoder.decode(token).getSubject()).isEqualTo("user-1");
    }

    @Test
    void decoder_shouldRefuseAnExpiredToken() {
        String token = sign(encoder, claims("lasono", minutesFromNow(-60), minutesFromNow(-45)));

        assertThatThrownBy(() -> decoder.decode(token)).isInstanceOf(JwtException.class);
    }

    @Test
    void decoder_shouldRefuseATokenSignedWithAnotherSecret() {
        String token = sign(config.jwtEncoder(OTHER_SECRET), claims("lasono", minutesFromNow(-1), minutesFromNow(10)));

        assertThatThrownBy(() -> decoder.decode(token)).isInstanceOf(JwtException.class);
    }

    @Test
    void decoder_shouldRefuseATokenFromAnotherIssuer() {
        String token = sign(encoder, claims("someone-else", minutesFromNow(-1), minutesFromNow(10)));

        assertThatThrownBy(() -> decoder.decode(token)).isInstanceOf(JwtException.class);
    }

    // The attacker removes the signature and says "alg": "none" so that nothing needs to be checked.
    @Test
    void decoder_shouldRefuseAnUnsignedToken() {
        String header = base64Url("{\"alg\":\"none\"}");
        String payload = base64Url("{\"iss\":\"lasono\",\"sub\":\"user-1\",\"exp\":" + minutesFromNow(10).getEpochSecond() + "}");

        assertThatThrownBy(() -> decoder.decode(header + "." + payload + ".")).isInstanceOf(JwtException.class);
    }

    // Same secret, but a different algorithm: the decoder must stay on the one it was set up for.
    @Test
    void decoder_shouldRefuseAnotherAlgorithmEvenWithTheSameSecret() {
        String longSecret = "x".repeat(64);
        JwtEncoder hs512Encoder = config.jwtEncoder(longSecret);
        JwtDecoder hs256Decoder = config.jwtDecoder(longSecret);
        JwtClaimsSet claims = claims("lasono", minutesFromNow(-1), minutesFromNow(10));
        String token = hs512Encoder
            .encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS512).build(), claims))
            .getTokenValue();

        assertThatThrownBy(() -> hs256Decoder.decode(token)).isInstanceOf(JwtException.class);
    }

    private static JwtClaimsSet claims(String issuer, Instant issuedAt, Instant expiresAt) {
        return JwtClaimsSet.builder().issuer(issuer).subject("user-1").issuedAt(issuedAt).expiresAt(expiresAt).build();
    }

    private static String sign(JwtEncoder encoder, JwtClaimsSet claims) {
        return encoder
            .encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims))
            .getTokenValue();
    }

    private static Instant minutesFromNow(long minutes) {
        return Instant.now().plus(minutes, ChronoUnit.MINUTES);
    }

    private static String base64Url(String text) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(text.getBytes(StandardCharsets.UTF_8));
    }
}
