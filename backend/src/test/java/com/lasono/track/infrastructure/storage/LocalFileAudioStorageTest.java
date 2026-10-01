package com.lasono.track.infrastructure.storage;

import static org.junit.jupiter.api.Assertions.*;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.application.port.out.StorageKeyInvalidException;
import com.lasono.track.domain.audio.model.AudioFormat;

class LocalFileAudioStorageTest {

    private LocalFileAudioStorage storage;

    @TempDir
    Path tempDir;

    @BeforeEach
    void setUp() {
        storage = new LocalFileAudioStorage(tempDir.toString());
    }

    @Test
    void store_shouldSaveFileToDirectoryAndReturnKey() throws IOException {
        String content = "dummy audio data";
        InputStream in = new ByteArrayInputStream(content.getBytes());

        StorageKey key = storage.store(in, AudioFormat.MP3);

        assertNotNull(key);
        assertTrue(key.value().matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.mp3"),
                "Key phải có dạng UUID.mp3, thực tế: " + key.value());

        Path savedFile = tempDir.resolve(key.value());
        assertTrue(Files.exists(savedFile));
        assertEquals(content, Files.readString(savedFile));
    }

    @Test
    void retrieve_shouldReturnInputStreamOfSavedFile() throws IOException {
        String content = "dummy audio data";
        StorageKey key = storage.store(new ByteArrayInputStream(content.getBytes()), AudioFormat.MP3);

        try (InputStream retrieved = storage.retrieve(key)) {
            assertNotNull(retrieved);
            String retrievedContent = new String(retrieved.readAllBytes());
            assertEquals(content, retrievedContent);
        }
    }

    @Test
    void delete_shouldRemoveFileFromDirectory() {
        StorageKey key = storage.store(new ByteArrayInputStream("data".getBytes()), AudioFormat.MP3);
        Path savedFile = tempDir.resolve(key.value());
        assertTrue(Files.exists(savedFile));

        storage.delete(key);

        assertFalse(Files.exists(savedFile));
    }

    @Test
    void retrieve_shouldThrowExceptionWhenFileNotFound() {
        StorageKey missingKey = new StorageKey("missing.mp3");
        assertThrows(AudioStorageException.class, () -> storage.retrieve(missingKey));
    }

    @Test
    void delete_shouldNotThrowWhenFileDoesNotExist() {
        StorageKey missingKey = new StorageKey("nonexistent.mp3");
        assertDoesNotThrow(() -> storage.delete(missingKey));
    }

        @Test
    void retrieveRangeReturnsOnlyRequestedBytes() throws IOException {
        StorageKey key = storage.store(new ByteArrayInputStream("0123456789".getBytes()), AudioFormat.MP3);

        try (InputStream in = storage.retrieveRange(key, 2, 4)) {
            assertEquals("2345", new String(in.readAllBytes()));
        }
    }

    @Test
    void retrieveRangeStopsAtEndOfFileWhenLengthIsLarger() throws IOException {
        StorageKey key = storage.store(new ByteArrayInputStream("0123456789".getBytes()), AudioFormat.MP3);

        try (InputStream in = storage.retrieveRange(key, 7, 100)) {
            assertEquals("789", new String(in.readAllBytes()));
        }
    }

    @Test
    void retrieveRangeRejectsNegativeOffset() {
        StorageKey key = storage.store(new ByteArrayInputStream("abc".getBytes()), AudioFormat.MP3);

        assertThrows(IllegalArgumentException.class, () -> storage.retrieveRange(key, -1, 2));
    }

    @Test
    void retrieveRangeRejectsKeyThatEscapesStorageRoot() throws IOException {
        Path root = Files.createDirectory(tempDir.resolve("root"));
        Files.writeString(tempDir.resolve("secret.txt"), "secret");
        LocalFileAudioStorage isolated = new LocalFileAudioStorage(root.toString());

        StorageKey key = new StorageKey("../secret.txt");

        assertThrows(StorageKeyInvalidException.class, () -> isolated.retrieveRange(key, 0, 6));
    }

    @Test
    void retrieveRejectsKeyThatEscapesStorageRoot() throws IOException {
        Path root = Files.createDirectory(tempDir.resolve("root"));
        Files.writeString(tempDir.resolve("secret.txt"), "secret");
        LocalFileAudioStorage isolated = new LocalFileAudioStorage(root.toString());

        StorageKey key = new StorageKey("../secret.txt");

        assertThrows(StorageKeyInvalidException.class, () -> isolated.retrieve(key));
    }

    @Test
    void deleteRejectsKeyThatEscapesStorageRootAndKeepsOutsideFile() throws IOException {
        Path root = Files.createDirectory(tempDir.resolve("root"));
        Path outside = tempDir.resolve("secret.txt");
        Files.writeString(outside, "secret");
        LocalFileAudioStorage isolated = new LocalFileAudioStorage(root.toString());

        StorageKey key = new StorageKey("../secret.txt");

        assertThrows(StorageKeyInvalidException.class, () -> isolated.delete(key));
        assertTrue(Files.exists(outside));
    }
}
