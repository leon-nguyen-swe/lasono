package com.lasono.track.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.lasono.track.domain.audio.exception.AudioResourceInvalidStateException;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.AudioResourceStatus;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.exception.TrackInvalidStateException;
import com.lasono.track.domain.model.TrackStatus;
import com.lasono.track.domain.model.Visibility;

class TrackTest {

    @Test
    void shouldStartInProcessing() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
            "Test Track",
            null
        );

        assertEquals(TrackStatus.PROCESSING, track.getStatus());
    }

    @Test
    void shouldCompleteProcessingWhenAudioResourceIsReady() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
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
    void shouldMoveTrackAndAudioResourceToFailedWhenProcessingFails() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
            "Test Track",
            null
        );

        track.uploadCompleted(
            new OriginalAudio(
                "original/test.wav",
                AudioFormat.WAV,
                1000L,
                "audio/wav"
            )
        );
        track.startProcessing();

        track.processingFailed();

        assertEquals(TrackStatus.FAILED, track.getStatus());
        assertEquals(AudioResourceStatus.FAILED, track.toSnapshot().audioResourceStatus());
    }

    @Test
    void shouldRejectFailingProcessingWhenTrackIsReady() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
            "Test Track",
            null
        );

        track.uploadCompleted(new OriginalAudio("original/test.wav", AudioFormat.WAV, 1000L, "audio/wav"));
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio("streaming/test.mp3", AudioFormat.MP3, 500L, "audio/mpeg"),
            new AudioDuration(180000L),
            new Waveform(java.util.List.of(0.1f, 0.5f, 0.2f))
        );

        assertThrows(
            TrackInvalidStateException.class,
            () -> track.processingFailed()
        );

        assertEquals(TrackStatus.READY, track.getStatus());
    }

    @Test
    void shouldRejectFailingProcessingWhenTrackIsAlreadyFailed() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
            "Test Track",
            null
        );

        track.uploadCompleted(new OriginalAudio("original/test.wav", AudioFormat.WAV, 1000L, "audio/wav"));
        track.startProcessing();
        track.processingFailed();

        assertThrows(
            TrackInvalidStateException.class,
            () -> track.processingFailed()
        );

        assertEquals(TrackStatus.FAILED, track.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingWhenTrackHasFailed() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
            "Test Track",
            null
        );

        track.uploadCompleted(new OriginalAudio("original/test.wav", AudioFormat.WAV, 1000L, "audio/wav"));
        track.startProcessing();
        track.processingFailed();

        assertThrows(
            TrackInvalidStateException.class,
            () -> track.processingCompleted(
                new StreamingAudio("streaming/test.mp3", AudioFormat.MP3, 500L, "audio/mpeg"),
                new AudioDuration(180000L),
                new Waveform(java.util.List.of(0.1f, 0.5f, 0.2f))
            )
        );

        assertEquals(TrackStatus.FAILED, track.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingWhenTrackIsNotProcessing() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
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
            TrackFixtures.OWNER,
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

    @Test
    void shouldKnowItsOwner() {
        OwnerId owner = new OwnerId(UUID.randomUUID());

        Track track = new Track(new TrackId(UUID.randomUUID()), owner, "Test Track", null);

        assertEquals(owner, track.getOwnerId());
    }

    // A track nobody owns could be edited by nobody and shown on nobody's profile, so it cannot exist.
    @Test
    void shouldNotExistWithoutAnOwner() {
        assertThrows(NullPointerException.class,
            () -> new Track(new TrackId(UUID.randomUUID()), null, "Test Track", null));
    }

    @Test
    void shouldShowItsOwnerInTheSnapshot() {
        OwnerId owner = new OwnerId(UUID.randomUUID());
        Track track = new Track(new TrackId(UUID.randomUUID()), owner, "Test Track", null);

        assertEquals(owner, track.toSnapshot().ownerId());
    }

    @Test
    void shouldKeepItsOwnerWhenRebuiltFromStorage() {
        OwnerId owner = new OwnerId(UUID.randomUUID());

        Track track = Track.reconstitute(
            new TrackId(UUID.randomUUID()),
            owner,
            "Test Track",
            null,
            Visibility.PUBLIC,
            TrackStatus.PROCESSING,
            new AudioResource(new AudioResourceId(UUID.randomUUID()))
        );

        assertEquals(owner, track.getOwnerId());
    }

    @Test
    void shouldBePublicUnlessItsOwnerChoosesOtherwise() {
        Track track = new Track(new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "Test Track", null);

        assertEquals(Visibility.PUBLIC, track.getVisibility());
    }

    @Test
    void shouldBePrivateWhenItsOwnerChoosesSo() {
        Track track = new Track(
            new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "Test Track", null, Visibility.PRIVATE);

        assertEquals(Visibility.PRIVATE, track.getVisibility());
        assertEquals(Visibility.PRIVATE, track.toSnapshot().visibility());
    }

    @Test
    void shouldNotExistWithoutAVisibility() {
        assertThrows(NullPointerException.class, () -> new Track(
            new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "Test Track", null, null));
    }

    @Test
    void shouldKeepItsVisibilityWhenRebuiltFromStorage() {
        Track track = Track.reconstitute(
            new TrackId(UUID.randomUUID()),
            TrackFixtures.OWNER,
            "Test Track",
            null,
            Visibility.PRIVATE,
            TrackStatus.PROCESSING,
            new AudioResource(new AudioResourceId(UUID.randomUUID()))
        );

        assertEquals(Visibility.PRIVATE, track.getVisibility());
    }
}
