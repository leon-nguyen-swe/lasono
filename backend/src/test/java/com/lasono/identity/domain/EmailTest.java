package com.lasono.identity.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import com.lasono.identity.domain.exception.EmailInvalidException;

class EmailTest {

    @Test
    void shouldKeepAValidEmail() {
        Email email = new Email("alice@example.com");

        assertEquals("alice@example.com", email.getValue());
    }

    @Test
    void shouldTrimAndLowercaseSoTheSameAccountHasOneEmail() {
        Email email = new Email("  Alice@Example.COM ");

        assertEquals("alice@example.com", email.getValue());
    }

    @Test
    void shouldRejectNull() {
        assertThrows(EmailInvalidException.class, () -> new Email(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "   ", "alice", "alice@", "@example.com", "alice@example", "a b@example.com", "a@@example.com"})
    void shouldRejectMalformedEmails(String value) {
        assertThrows(EmailInvalidException.class, () -> new Email(value));
    }

    @Test
    void shouldRejectEmailLongerThan254Characters() {
        String tooLong = "a".repeat(250) + "@example.com";

        assertThrows(EmailInvalidException.class, () -> new Email(tooLong));
    }

    @Test
    void shouldBeEqualWhenTheNormalizedValuesAreEqual() {
        assertEquals(new Email("Alice@example.com"), new Email("alice@EXAMPLE.com"));
        assertEquals(new Email("Alice@example.com").hashCode(), new Email("alice@EXAMPLE.com").hashCode());
        assertNotEquals(new Email("alice@example.com"), new Email("bob@example.com"));
    }
}
