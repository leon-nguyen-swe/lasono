package com.lasono.track.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.lasono.track.domain.audio.exception.AudioResourceInvalidException;
import com.lasono.track.domain.audio.exception.AudioResourceInvalidStateException;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.AudioResourceStatus;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;

public class AudioResourceTest {

    private AudioResource createResource() {
        return new AudioResource(
            new AudioResourceId(UUID.randomUUID())
        );
    }

    private OriginalAudio createOriginalAudio() {
        return new OriginalAudio(
            "original/audio.wav",
            AudioFormat.WAV,
            10_000L,
            "audio/wav"
        );
    }

    private StreamingAudio createStreamingAudio() {
        return new StreamingAudio(
            "streaming/audio.mp3",
            AudioFormat.MP3,
            8_000L,
            "audio/mpeg"
        );
    }

    private AudioDuration createAudioDuration() {
        return new AudioDuration(180_000L);
    }

    private Waveform createWaveform() {
        return new Waveform(List.of(0.1f, 0.5f, 0.8f, 0.3f));
    }

    @Test
    void shouldStartWithCreatedStatus() {
        AudioResource resource = createResource();

        assertEquals(AudioResourceStatus.CREATED, resource.getStatus());
    }

    @Test
    void shouldRejectNullId() {
        assertThrows(
            NullPointerException.class,
            () -> new AudioResource(null)
        );
    }

    @Test
    void shouldTransitionFromCreatedToUploaded() {
        AudioResource resource = createResource();
        OriginalAudio originalAudio = createOriginalAudio();

        resource.uploadCompleted(originalAudio);

        assertEquals(AudioResourceStatus.UPLOADED, resource.getStatus());
        assertEquals(originalAudio, resource.getOriginalAudio());
    }

    @Test
    void shouldRejectUploadWithNullOriginalAudio() {
        AudioResource resource = createResource();

        assertThrows(
            AudioResourceInvalidException.class,
            () -> resource.uploadCompleted(null)
        );

        assertEquals(AudioResourceStatus.CREATED, resource.getStatus());
        assertEquals(null, resource.getOriginalAudio());
    }

    @Test
    void shouldTransitionFromUploadedToProcessing() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();

        assertEquals(AudioResourceStatus.PROCESSING, resource.getStatus());
    }

    @Test
    void shouldTransitionFromProcessingToReady() {
        AudioResource resource = createResource();
        OriginalAudio originalAudio = createOriginalAudio();
        StreamingAudio streamingAudio = createStreamingAudio();
        AudioDuration audioDuration = createAudioDuration();
        Waveform waveform = createWaveform();

        resource.uploadCompleted(originalAudio);
        resource.startProcessing();

        resource.processingCompleted(
            streamingAudio,
            audioDuration,
            waveform
        );

        assertEquals(AudioResourceStatus.READY, resource.getStatus());
        assertEquals(originalAudio, resource.getOriginalAudio());
        assertEquals(streamingAudio, resource.getStreamingAudio());
        assertEquals(audioDuration, resource.getAudioDuration());
        assertEquals(waveform, resource.getWaveform());
    }

    @Test
    void shouldRejectStartingProcessingFromCreated() {
        AudioResource resource = createResource();

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.startProcessing()
        );

        assertEquals(AudioResourceStatus.CREATED, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingFromCreated() {
        AudioResource resource = createResource();

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.processingCompleted(
                createStreamingAudio(),
                createAudioDuration(),
                createWaveform()
            )
        );

        assertEquals(AudioResourceStatus.CREATED, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingFromUploaded() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.processingCompleted(
                createStreamingAudio(),
                createAudioDuration(),
                createWaveform()
            )
        );

        assertEquals(AudioResourceStatus.UPLOADED, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingFromReady() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();
        resource.processingCompleted(
            createStreamingAudio(),
            createAudioDuration(),
            createWaveform()
        );

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.processingCompleted(
                createStreamingAudio(),
                createAudioDuration(),
                createWaveform()
            )
        );

        assertEquals(AudioResourceStatus.READY, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingUploadFromUploaded() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.uploadCompleted(createOriginalAudio())
        );

        assertEquals(AudioResourceStatus.UPLOADED, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingUploadFromProcessing() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.uploadCompleted(createOriginalAudio())
        );

        assertEquals(AudioResourceStatus.PROCESSING, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingUploadFromReady() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();
        resource.processingCompleted(
            createStreamingAudio(),
            createAudioDuration(),
            createWaveform()
        );

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.uploadCompleted(createOriginalAudio())
        );

        assertEquals(AudioResourceStatus.READY, resource.getStatus());
    }

    @Test
    void shouldRejectStartingProcessingFromProcessing() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();

        assertThrows(
            AudioResourceInvalidStateException.class,
            () -> resource.startProcessing()
        );

        assertEquals(AudioResourceStatus.PROCESSING, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingWithNullStreamingAudio() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();

        assertThrows(
            AudioResourceInvalidException.class,
            () -> resource.processingCompleted(
                null,
                createAudioDuration(),
                createWaveform()
            )
        );

        assertEquals(AudioResourceStatus.PROCESSING, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingWithNullAudioDuration() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();

        assertThrows(
            AudioResourceInvalidException.class,
            () -> resource.processingCompleted(
                createStreamingAudio(),
                null,
                createWaveform()
            )
        );

        assertEquals(AudioResourceStatus.PROCESSING, resource.getStatus());
    }

    @Test
    void shouldRejectCompletingProcessingWithNullWaveform() {
        AudioResource resource = createResource();

        resource.uploadCompleted(createOriginalAudio());
        resource.startProcessing();

        assertThrows(
            AudioResourceInvalidException.class,
            () -> resource.processingCompleted(
                createStreamingAudio(),
                createAudioDuration(),
                null
            )
        );

        assertEquals(AudioResourceStatus.PROCESSING, resource.getStatus());
    }
}