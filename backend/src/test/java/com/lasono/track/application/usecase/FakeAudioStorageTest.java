package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.StorageKey;

/**
 * Unit tests for {@link FakeAudioStorage}.
 *
 * <p>FakeAudioStorage is an in-memory test double used to simulate a working
 * AudioStorage without touching the file system or any external service.
 */
class FakeAudioStorageTest {

    private FakeAudioStorage storage;

    @BeforeEach
    void setUp() {
        storage = new FakeAudioStorage();
    }

    // -----------------------------------------------------------------------
    // store()
    // -----------------------------------------------------------------------

    @Test
    void store_shouldReturnStorageKeyWithPrefixedFileName() {
        InputStream data = new ByteArrayInputStream("audio-bytes".getBytes());

        StorageKey key = storage.store(data, "track.mp3");

        assertEquals("fake/audio/track.mp3", key.value());
    }

    @Test
    void store_shouldReturnStorageKeyWithWavFileName() {
        InputStream data = new ByteArrayInputStream("audio-bytes".getBytes());

        StorageKey key = storage.store(data, "track.wav");

        assertEquals("fake/audio/track.wav", key.value());
    }

    @Test
    void store_shouldReturnDistinctKeysForDifferentFileNames() {
        InputStream data1 = new ByteArrayInputStream("bytes1".getBytes());
        InputStream data2 = new ByteArrayInputStream("bytes2".getBytes());

        StorageKey key1 = storage.store(data1, "a.mp3");
        StorageKey key2 = storage.store(data2, "b.mp3");

        // Keys must differ because the file names differ
        org.junit.jupiter.api.Assertions.assertNotEquals(key1.value(), key2.value());
    }

    @Test
    void store_shouldReturnNonNullKey() {
        InputStream data = new ByteArrayInputStream(new byte[0]);

        StorageKey key = storage.store(data, "empty.mp3");

        assertNotNull(key);
    }

    @Test
    void store_shouldReturnKeyWithPrefixOnlyWhenFileNameIsEmpty() {
        // "fake/audio/" is not blank, so StorageKey still accepts it —
        // the fake simply prefixes whatever fileName it receives.
        InputStream data = new ByteArrayInputStream("bytes".getBytes());

        StorageKey key = storage.store(data, "");

        assertEquals("fake/audio/", key.value());
    }

    @Test
    void store_shouldHandleNullInputStream() {
        // FakeAudioStorage does not read the stream, so null should not cause an NPE
        assertDoesNotThrow(() -> storage.store(null, "track.mp3"));
    }

    @Test
    void store_shouldHandleSpecialCharactersInFileName() {
        InputStream data = new ByteArrayInputStream("bytes".getBytes());

        StorageKey key = storage.store(data, "my track (1).mp3");

        assertEquals("fake/audio/my track (1).mp3", key.value());
    }

    // -----------------------------------------------------------------------
    // retrieve()
    // -----------------------------------------------------------------------

    @Test
    void retrieve_shouldReturnNonNullInputStream() {
        StorageKey key = new StorageKey("fake/audio/track.mp3");

        InputStream stream = storage.retrieve(key);

        assertNotNull(stream);
    }

    @Test
    void retrieve_shouldReturnEmptyInputStream() throws IOException {
        StorageKey key = new StorageKey("fake/audio/track.mp3");

        InputStream stream = storage.retrieve(key);

        assertEquals(-1, stream.read(), "Stream should be empty (no bytes available)");
    }

    @Test
    void retrieve_shouldNotThrowForAnyValidKey() {
        StorageKey key = new StorageKey("any/valid/key");

        assertDoesNotThrow(() -> storage.retrieve(key));
    }

    // -----------------------------------------------------------------------
    // retrieveRange()
    // -----------------------------------------------------------------------

    @Test
    void retrieveRange_shouldReturnNonNullInputStream() {
        StorageKey key = new StorageKey("fake/audio/track.mp3");

        InputStream stream = storage.retrieveRange(key, 0, 512);

        assertNotNull(stream);
    }

    @Test
    void retrieveRange_shouldReturnEmptyInputStream() throws IOException {
        StorageKey key = new StorageKey("fake/audio/track.mp3");

        InputStream stream = storage.retrieveRange(key, 100, 200);

        assertEquals(-1, stream.read(), "Range stream should be empty (test double)");
    }

    // -----------------------------------------------------------------------
    // delete()
    // -----------------------------------------------------------------------

    @Test
    void delete_shouldNotThrow() {
        StorageKey key = new StorageKey("fake/audio/track.mp3");

        assertDoesNotThrow(() -> storage.delete(key));
    }

    @Test
    void delete_shouldBeNoOp_callMultipleTimes() {
        StorageKey key = new StorageKey("fake/audio/track.mp3");

        // Calling delete multiple times must not throw
        assertDoesNotThrow(() -> {
            storage.delete(key);
            storage.delete(key);
        });
    }
}
