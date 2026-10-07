package com.lasono.track.application.usecase;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Map;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.audio.model.AudioFormat;

/** Keeps the stored files in memory, so a test can see what was stored, read back and deleted. */
class InMemoryAudioStorage implements AudioStorage {

    final Map<String, byte[]> files = new LinkedHashMap<>();
    private int nextNumber;

    @Override
    public StorageKey store(InputStream audioData, AudioFormat audioFormat) {
        StorageKey key = new StorageKey("memory-" + nextNumber++ + "." + audioFormat.getExtension());
        try {
            files.put(key.value(), audioData.readAllBytes());
        } catch (IOException e) {
            throw new AudioStorageException("Failed to read the audio to store", e);
        }
        return key;
    }

    @Override
    public InputStream retrieve(StorageKey key) {
        byte[] content = files.get(key.value());
        if (content == null) {
            throw new AudioStorageException("No such file: " + key.value(), new IllegalStateException());
        }
        return new ByteArrayInputStream(content);
    }

    @Override
    public InputStream retrieveRange(StorageKey key, long offset, long length) {
        byte[] content = files.get(key.value());
        if (content == null) {
            throw new AudioStorageException("No such file: " + key.value(), new IllegalStateException());
        }
        return new ByteArrayInputStream(content, (int) offset, (int) length);
    }

    @Override
    public void delete(StorageKey key) {
        files.remove(key.value());
    }
}
