package com.lasono.track.application.port.out;

import java.io.InputStream;

public interface AudioStorage {

    StorageKey store(InputStream audioData, String originalFileName);

    InputStream retrieve(StorageKey key);

    InputStream retrieveRange(StorageKey key, long offset, long lengtg);

    void delete(StorageKey key);
}