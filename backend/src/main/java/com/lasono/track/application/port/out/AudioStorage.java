package com.lasono.track.application.port.out;

import java.io.InputStream;

public interface AudioStorage {

    StorageKey store(InputStream audioData, String originalFileName);

    InputStream retrieve(StorageKey key);

    void delete(StorageKey key);
}