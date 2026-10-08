package com.lasono.identity.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import com.lasono.identity.domain.exception.DisplayNameInvalidException;

class DisplayNameTest {

    @Test
    void shouldKeepAValidName() {
        assertEquals("Alice", new DisplayName("Alice").getValue());
    }

    @Test
    void shouldKeepVietnameseCharacters() {
        assertEquals("Nguyễn Văn Á", new DisplayName("Nguyễn Văn Á").getValue());
    }

    @Test
    void shouldTrimSurroundingWhitespace() {
        assertEquals("Alice", new DisplayName("  Alice  ").getValue());
    }

    @Test
    void shouldRejectNull() {
        assertThrows(DisplayNameInvalidException.class, () -> new DisplayName(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "   ", "\t\n"})
    void shouldRejectBlankNames(String value) {
        assertThrows(DisplayNameInvalidException.class, () -> new DisplayName(value));
    }

    @Test
    void shouldAcceptExactly50Characters() {
        String fifty = "a".repeat(50);

        assertEquals(fifty, new DisplayName(fifty).getValue());
    }

    @Test
    void shouldRejectMoreThan50Characters() {
        assertThrows(DisplayNameInvalidException.class, () -> new DisplayName("a".repeat(51)));
    }

    @Test
    void shouldBeEqualWhenTheValuesAreEqual() {
        assertEquals(new DisplayName("Alice"), new DisplayName(" Alice "));
        assertEquals(new DisplayName("Alice").hashCode(), new DisplayName(" Alice ").hashCode());
        assertNotEquals(new DisplayName("Alice"), new DisplayName("Bob"));
    }
}
