package com.lasono.track.application.usecase;

import java.io.ByteArrayInputStream;
import java.io.InputStream;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;

class FailingAudioStorage implements AudioStorage {

    @Override
    public StorageKey store(InputStream audioData, String originalFileName) {
        throw new AudioStorageException("Storage unavailable", new RuntimeException("disk full"));
    }

    @Override
    public InputStream retrieve(StorageKey key) {
        return new ByteArrayInputStream(new byte[0]);
    }

    @Override
    public void delete(StorageKey key) {
        // no-op
    }
}
