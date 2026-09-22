package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;

/**
 * Unit tests for {@link FailingAudioStorage}.
 *
 * <p>FailingAudioStorage is a test double that simulates an unavailable
 * storage backend. It is used to verify that callers handle
 * {@link AudioStorageException} correctly (e.g. in
 * {@code UploadTrackUseCaseTest}).
 */
class FailingAudioStorageTest {

    private FailingAudioStorage storage;

    @BeforeEach
    void setUp() {
        storage = new FailingAudioStorage();
    }

    // -----------------------------------------------------------------------
    // store() — must always throw AudioStorageException
    // -----------------------------------------------------------------------

    @Test
    void store_shouldThrowAudioStorageException() {
        InputStream data = new ByteArrayInputStream("audio-bytes".getBytes());

        assertThrows(AudioStorageException.class,
                () -> storage.store(data, "track.mp3"));
    }

    @Test
    void store_shouldThrowWithExpectedMessage() {
        InputStream data = new ByteArrayInputStream("audio-bytes".getBytes());

        AudioStorageException ex = assertThrows(AudioStorageException.class,
                () -> storage.store(data, "track.mp3"));

        assertEquals("Storage unavailable", ex.getMessage());
    }

    @Test
    void store_shouldThrowWithRootCause() {
        InputStream data = new ByteArrayInputStream("audio-bytes".getBytes());

        AudioStorageException ex = assertThrows(AudioStorageException.class,
                () -> storage.store(data, "track.mp3"));

        assertNotNull(ex.getCause(), "AudioStorageException must wrap the root cause");
    }

    @Test
    void store_shouldThrowForAnyFileName() {
        InputStream data = new ByteArrayInputStream(new byte[0]);

        assertThrows(AudioStorageException.class,
                () -> storage.store(data, "completely-different.wav"));
    }

    @Test
    void store_shouldThrowForNullInputStream() {
        // Even without data, storage failure must propagate before any read
        assertThrows(AudioStorageException.class,
                () -> storage.store(null, "track.mp3"));
    }

    // -----------------------------------------------------------------------
    // retrieve() — intentionally does NOT fail (simulates partial failure)
    // -----------------------------------------------------------------------

    @Test
    void retrieve_shouldReturnNonNullInputStream() {
        StorageKey key = new StorageKey("some/storage/key");

        InputStream stream = storage.retrieve(key);

        assertNotNull(stream);
    }

    @Test
    void retrieve_shouldReturnEmptyInputStream() throws IOException {
        StorageKey key = new StorageKey("some/storage/key");

        InputStream stream = storage.retrieve(key);

        assertEquals(-1, stream.read(), "Stream should be empty for the failing stub");
    }

    @Test
    void retrieve_shouldNotThrow() {
        StorageKey key = new StorageKey("some/storage/key");

        assertDoesNotThrow(() -> storage.retrieve(key));
    }

    // -----------------------------------------------------------------------
    // retrieveRange() — intentionally does NOT fail
    // -----------------------------------------------------------------------

    @Test
    void retrieveRange_shouldReturnNonNullInputStream() {
        StorageKey key = new StorageKey("some/storage/key");

        InputStream stream = storage.retrieveRange(key, 0, 256);

        assertNotNull(stream);
    }

    @Test
    void retrieveRange_shouldReturnEmptyInputStream() throws IOException {
        StorageKey key = new StorageKey("some/storage/key");

        InputStream stream = storage.retrieveRange(key, 100, 200);

        assertEquals(-1, stream.read(), "Range stream should be empty for the failing stub");
    }

    @Test
    void retrieveRange_shouldNotThrow() {
        StorageKey key = new StorageKey("some/storage/key");

        assertDoesNotThrow(() -> storage.retrieveRange(key, 0, 512));
    }

    // -----------------------------------------------------------------------
    // delete() — intentionally does NOT fail (no-op)
    // -----------------------------------------------------------------------

    @Test
    void delete_shouldNotThrow() {
        StorageKey key = new StorageKey("some/storage/key");

        assertDoesNotThrow(() -> storage.delete(key));
    }

    @Test
    void delete_shouldBeNoOp_callMultipleTimes() {
        StorageKey key = new StorageKey("some/storage/key");

        assertDoesNotThrow(() -> {
            storage.delete(key);
            storage.delete(key);
        });
    }
}
