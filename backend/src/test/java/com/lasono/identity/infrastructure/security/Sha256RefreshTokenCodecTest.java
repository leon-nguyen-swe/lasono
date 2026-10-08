package com.lasono.identity.infrastructure.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Base64;
import java.util.HashSet;
import java.util.Set;

import org.junit.jupiter.api.Test;

class Sha256RefreshTokenCodecTest {

    private final Sha256RefreshTokenCodec codec = new Sha256RefreshTokenCodec();

    // 32 bytes = 256 bits. Written as base64url without padding that is 43 characters, safe inside a cookie.
    @Test
    void generate_shouldGive256BitsWrittenAsBase64UrlWithoutPadding() {
        String token = codec.generate();

        assertThat(token).matches("[A-Za-z0-9_-]{43}");
        assertThat(Base64.getUrlDecoder().decode(token)).hasSize(32);
    }

    @Test
    void generate_shouldGiveADifferentValueEveryTime() {
        Set<String> tokens = new HashSet<>();
        for (int i = 0; i < 1000; i++) {
            tokens.add(codec.generate());
        }

        assertThat(tokens).hasSize(1000);
    }

    // The standard test vector for SHA-256: a hash that merely looks like hex would not pass this.
    @Test
    void hash_shouldBeTheSha256OfTheValueAsLowerCaseHex() {
        assertThat(codec.hash("abc"))
            .isEqualTo("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

    @Test
    void hash_shouldGiveTheSameHashForTheSameValueAndAnotherForAnotherValue() {
        assertThat(codec.hash("token-1")).isEqualTo(codec.hash("token-1"));
        assertThat(codec.hash("token-1")).isNotEqualTo(codec.hash("token-2"));
    }

    @Test
    void hash_shouldNotHideAMissingValueBehindSomeHash() {
        assertThatThrownBy(() -> codec.hash(null)).isInstanceOf(NullPointerException.class);
    }
}
