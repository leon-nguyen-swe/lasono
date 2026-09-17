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
        String originalFileName = "test.mp3";

        StorageKey key = storage.store(in, originalFileName);

        assertNotNull(key);
        assertTrue(key.value().endsWith(originalFileName));

        Path savedFile = tempDir.resolve(key.value());
        assertTrue(Files.exists(savedFile));
        assertEquals(content, Files.readString(savedFile));
    }

    @Test
    void retrieve_shouldReturnInputStreamOfSavedFile() throws IOException {
        String content = "dummy audio data";
        StorageKey key = storage.store(new ByteArrayInputStream(content.getBytes()), "test.mp3");

        try (InputStream retrieved = storage.retrieve(key)) {
            assertNotNull(retrieved);
            String retrievedContent = new String(retrieved.readAllBytes());
            assertEquals(content, retrievedContent);
        }
    }

    @Test
    void delete_shouldRemoveFileFromDirectory() {
        StorageKey key = storage.store(new ByteArrayInputStream("data".getBytes()), "test.mp3");
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
}
