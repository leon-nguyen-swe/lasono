package com.lasono.track.infrastructure.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.junit.jupiter.api.Test;

class HmacStreamUrlSignerTest {

    private static final String SECRET = "a-test-secret-that-is-at-least-32-bytes";
    private static final UUID TRACK = UUID.fromString("5b0c2d4e-1111-4222-8333-944455566677");
    private static final long EXPIRES = 1_800_000_000L;

    private final HmacStreamUrlSigner signer = new HmacStreamUrlSigner(SECRET);

    // The message format is pinned on purpose: the "stream:" prefix keeps this signature from ever being
    // valid as anything else made with the same key, such as a login token.
    @Test
    void sign_shouldBeTheHmacSha256OfTheTrackAndTheExpiryAsBase64Url() throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(SECRET.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        byte[] expected = mac.doFinal(("stream:" + TRACK + ":" + EXPIRES).getBytes(StandardCharsets.UTF_8));

        String signature = signer.sign(TRACK, EXPIRES);

        assertThat(signature).matches("[A-Za-z0-9_-]{43}");
        assertThat(Base64.getUrlDecoder().decode(signature)).isEqualTo(expected);
    }

    @Test
    void sign_shouldGiveTheSameSignatureForTheSameInput() {
        assertThat(signer.sign(TRACK, EXPIRES)).isEqualTo(signer.sign(TRACK, EXPIRES));
    }

    @Test
    void sign_shouldDifferForAnotherTrackAnotherExpiryOrAnotherSecret() {
        String signature = signer.sign(TRACK, EXPIRES);

        assertThat(signer.sign(UUID.randomUUID(), EXPIRES)).isNotEqualTo(signature);
        assertThat(signer.sign(TRACK, EXPIRES + 1)).isNotEqualTo(signature);
        assertThat(new HmacStreamUrlSigner("another-secret-with-at-least-32-bytes!").sign(TRACK, EXPIRES))
            .isNotEqualTo(signature);
    }

    @Test
    void isValid_shouldAcceptTheSignatureItMade() {
        assertThat(signer.isValid(TRACK, EXPIRES, signer.sign(TRACK, EXPIRES))).isTrue();
    }

    // A signature is worth exactly one track until exactly one moment.
    @Test
    void isValid_shouldRefuseThatSignatureForAnotherTrackOrAnotherExpiry() {
        String signature = signer.sign(TRACK, EXPIRES);

        assertThat(signer.isValid(UUID.randomUUID(), EXPIRES, signature)).isFalse();
        assertThat(signer.isValid(TRACK, EXPIRES + 1, signature)).isFalse();
    }

    @Test
    void isValid_shouldRefuseASignatureMadeWithAnotherSecret() {
        String foreign = new HmacStreamUrlSigner("another-secret-with-at-least-32-bytes!").sign(TRACK, EXPIRES);

        assertThat(signer.isValid(TRACK, EXPIRES, foreign)).isFalse();
    }

    @Test
    void isValid_shouldRefuseATamperedSignature() {
        String signature = signer.sign(TRACK, EXPIRES);
        char first = signature.charAt(0);
        String tampered = (first == 'A' ? 'B' : 'A') + signature.substring(1);

        assertThat(signer.isValid(TRACK, EXPIRES, tampered)).isFalse();
        assertThat(signer.isValid(TRACK, EXPIRES, signature.substring(1))).isFalse();
        assertThat(signer.isValid(TRACK, EXPIRES, signature + "A")).isFalse();
    }

    // The check is open to strangers, so rubbish must end in "no" and never in an exception.
    @Test
    void isValid_shouldAnswerNoToMissingOrMalformedSignatures() {
        assertThat(signer.isValid(TRACK, EXPIRES, null)).isFalse();
        assertThat(signer.isValid(TRACK, EXPIRES, "")).isFalse();
        assertThat(signer.isValid(TRACK, EXPIRES, "   ")).isFalse();
        assertThat(signer.isValid(TRACK, EXPIRES, "not base64 !!!")).isFalse();
        assertThat(signer.isValid(TRACK, EXPIRES, "%%%%")).isFalse();
    }

    @Test
    void constructor_shouldRefuseASecretThatIsMissingOrTooShort() {
        assertThatThrownBy(() -> new HmacStreamUrlSigner(null)).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new HmacStreamUrlSigner("")).isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new HmacStreamUrlSigner("too-short")).isInstanceOf(IllegalArgumentException.class);
    }
}
