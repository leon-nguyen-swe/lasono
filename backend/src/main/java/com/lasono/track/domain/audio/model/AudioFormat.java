package com.lasono.track.domain.audio.model;

import com.lasono.track.domain.audio.exception.AudioFormatInvalidException;

public enum AudioFormat {
    MP3,
    WAV;

    public static AudioFormat fromMimeType(String mimeType) {
        if (mimeType == null) {
            throw new AudioFormatInvalidException("MIME type must not be null");
        }
        return switch (mimeType) {
            case "audio/mpeg" -> MP3;
            case "audio/wav", "audio/x-wav" -> WAV;
            default -> throw new AudioFormatInvalidException("Unsupported MIME type: " + mimeType);
        };
    }
}