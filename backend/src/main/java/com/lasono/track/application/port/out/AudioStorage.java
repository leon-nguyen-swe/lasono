package com.lasono.track.application.port.out;

import java.io.InputStream;

import com.lasono.track.domain.audio.model.AudioFormat;

public interface AudioStorage {

    StorageKey store(InputStream audioData, AudioFormat audioFormat);

    InputStream retrieve(StorageKey key);

    InputStream retrieveRange(StorageKey key, long offset, long length);

    void delete(StorageKey key);
}