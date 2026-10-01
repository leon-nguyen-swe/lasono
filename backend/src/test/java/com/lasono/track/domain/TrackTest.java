package com.lasono.track.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.lasono.track.domain.audio.exception.AudioResourceInvalidStateException;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.exception.TrackInvalidStateException;
import com.lasono.track.domain.model.TrackStatus;

class TrackTest {

    @Test
    void shouldStartInProcessing() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            "Test Track",
            null
        );

        assertEquals(TrackStatus.PROCESSING, track.getStatus());
    }

    @Test
    void shouldCompleteProcessingWhenAudioResourceIsReady() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            "Test Track",
            null
        );

        OriginalAudio originalAudio = new OriginalAudio(
            "original/test.wav",
            AudioFormat.WAV,
            1000L,
            "audio/wav"
        );

        StreamingAudio streamingAudio = new StreamingAudio(
            "streaming/test.mp3",
            AudioFormat.MP3,
            500L,
            "audio/mpeg"
        );

        AudioDuration audioDuration = new AudioDuration(180000L);

        Waveform waveform = new Waveform(
            java.util.List.of(0.1f, 0.5f, 0.2f)
        );

        track.uploadCompleted(originalAudio);
        track.startProcessing();
        track.processingCompleted(
            streamingAudio,
            audioDuration,
            waveform
        );

        assertEquals(TrackStatus.READY, track.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingWhenTrackIsNotProcessing() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            "Test Track",
            null
        );

        StreamingAudio streamingAudio = new StreamingAudio(
            "streaming/test.mp3",
            AudioFormat.MP3,
            500L,
            "audio/mpeg"
        );

        AudioDuration audioDuration = new AudioDuration(180000L);

        Waveform waveform = new Waveform(
            java.util.List.of(0.1f, 0.5f, 0.2f)
        );

        OriginalAudio originalAudio = new OriginalAudio(    "original/test.wav", AudioFormat.WAV, 1000L, "audio/wav");

        track.uploadCompleted(originalAudio);
        track.startProcessing();
        track.processingCompleted(streamingAudio, audioDuration, waveform);

        assertThrows(
            TrackInvalidStateException.class,
            () -> track.processingCompleted(
                streamingAudio,
                audioDuration,
                waveform
            )
        );

        assertEquals(TrackStatus.READY, track.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingWhenAudioResourceIsNotProcessing() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            "Test Track",
            null
        );

        StreamingAudio streamingAudio = new StreamingAudio(
            "streaming/test.mp3",
            AudioFormat.MP3,
            500L,
            "audio/mpeg"
        );

        AudioDuration audioDuration = new AudioDuration(180000L);

        Waveform waveform = new Waveform(
            java.util.List.of(0.1f, 0.5f, 0.2f)
        );

        track.uploadCompleted(
            new OriginalAudio(
                "original/test.wav",
                AudioFormat.WAV,
                1000L,
                "audio/wav"
            )
        );

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> track.processingCompleted(
                streamingAudio,
                audioDuration,
                waveform
            )
        );

        assertEquals(TrackStatus.PROCESSING, track.getStatus());
    }
}