package com.lasono.track.domain.audio.model;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

import com.lasono.track.domain.audio.exception.OriginalAudioInvalidException;

class OriginalAudioTest {

    @Test
    void shouldCreateWithValidData() {
        OriginalAudio audio = new OriginalAudio(
            "audio/original/song.wav",
            AudioFormat.WAV,
            1024,
            "audio/wav"
        );

        assertEquals("audio/original/song.wav", audio.getStorageKey());
        assertEquals(AudioFormat.WAV, audio.getFormat());
        assertEquals(1024, audio.getFileSize());
        assertEquals("audio/wav", audio.getMimeType());
    }

    @Test
    void shouldRejectNullStorageKey() {
        assertThrows(
            OriginalAudioInvalidException.class,
            () -> new OriginalAudio(
                null,
                AudioFormat.WAV,
                1024,
                "audio/wav"
            )
        );
    }

    @Test
    void shouldRejectBlankStorageKey() {
        assertThrows(
            OriginalAudioInvalidException.class,
            () -> new OriginalAudio(
                "   ",
                AudioFormat.WAV,
                1024,
                "audio/wav"
            )
        );
    }

    @Test
    void shouldRejectNullFormat() {
        assertThrows(
            OriginalAudioInvalidException.class,
            () -> new OriginalAudio(
                "audio/original/song.wav",
                null,
                1024,
                "audio/wav"
            )
        );
    }

    @Test
    void shouldRejectZeroFileSize() {
        assertThrows(
            OriginalAudioInvalidException.class,
            () -> new OriginalAudio(
                "audio/original/song.wav",
                AudioFormat.WAV,
                0,
                "audio/wav"
            )
        );
    }

    @Test
    void shouldRejectNegativeFileSize() {
        assertThrows(
            OriginalAudioInvalidException.class,
            () -> new OriginalAudio(
                "audio/original/song.wav",
                AudioFormat.WAV,
                -1,
                "audio/wav"
            )
        );
    }

    @Test
    void shouldRejectNullMimeType() {
        assertThrows(
            OriginalAudioInvalidException.class,
            () -> new OriginalAudio(
                "audio/original/song.wav",
                AudioFormat.WAV,
                1024,
                null
            )
        );
    }

    @Test
    void shouldRejectBlankMimeType() {
        assertThrows(
            OriginalAudioInvalidException.class,
            () -> new OriginalAudio(
                "audio/original/song.wav",
                AudioFormat.WAV,
                1024,
                "   "
            )
        );
    }
}