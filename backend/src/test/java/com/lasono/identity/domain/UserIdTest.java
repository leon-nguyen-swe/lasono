package com.lasono.identity.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.Test;

class UserIdTest {

    @Test
    void shouldExposeTheUuid() {
        UUID uuid = UUID.randomUUID();

        assertEquals(uuid, new UserId(uuid).getValue());
    }

    @Test
    void shouldRejectNull() {
        assertThrows(NullPointerException.class, () -> new UserId(null));
    }

    @Test
    void shouldBeEqualWhenTheUuidsAreEqual() {
        UUID uuid = UUID.randomUUID();

        assertEquals(new UserId(uuid), new UserId(uuid));
        assertEquals(new UserId(uuid).hashCode(), new UserId(uuid).hashCode());
        assertNotEquals(new UserId(uuid), new UserId(UUID.randomUUID()));
    }
}
