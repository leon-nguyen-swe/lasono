package com.lasono.track.application.usecase;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.StorageKey;

/** Removes a stored file that is no longer needed after an operation failed. */
class StoredAudioCleanup {

    private final AudioStorage audioStorage;

    StoredAudioCleanup(AudioStorage audioStorage) {
        this.audioStorage = audioStorage;
    }

    /**
     * Deletes the file. A failure to delete must not hide {@code cause}, the error that made the
     * cleanup necessary, so it is attached to it as a suppressed exception instead of being thrown.
     */
    void deleteQuietly(StorageKey key, RuntimeException cause) {
        try {
            audioStorage.delete(key);
        } catch (RuntimeException cleanupFailure) {
            cause.addSuppressed(cleanupFailure);
        }
    }
}
