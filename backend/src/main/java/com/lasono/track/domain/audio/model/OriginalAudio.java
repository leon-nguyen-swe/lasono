package com.lasono.track.domain.audio.model;

import com.lasono.track.domain.audio.exception.OriginalAudioInvalidException;

public class OriginalAudio {

    private final String storageKey;
    private final AudioFormat format;
    private final long fileSize;
    private final String mimeType;
    
    public OriginalAudio(
        String storageKey,
        AudioFormat format,
        long fileSize,
        String mimeType
    ) {
        validateRequired(storageKey, "Storage Key");
        this.storageKey = storageKey;
        if (format == null) {
            throw new OriginalAudioInvalidException("Format must not be null");
        }
        this.format = format;
        if (fileSize <= 0) {
            throw new OriginalAudioInvalidException("File size must be greater than 0");
        }
        this.fileSize = fileSize;
        validateRequired(mimeType, "MIME type");
        this.mimeType = mimeType;
    }

    public String getStorageKey() {
        return this.storageKey;
    }

    public AudioFormat getFormat() {
        return this.format;
    }

    public long getFileSize() {
        return fileSize;
    }

    public String getMimeType() {
        return mimeType;
    }

    private void validateRequired(String value, String fieldName) {
        if (value == null) {
            throw new OriginalAudioInvalidException(fieldName + " must not be null");
        }
        if (value.isBlank()) {
            throw new OriginalAudioInvalidException(fieldName + " must not be blank");
        }
    } 
}