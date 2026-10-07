package com.lasono.track.application.usecase;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import com.lasono.track.application.port.out.AudioProcessingException;
import com.lasono.track.application.port.out.AudioProcessor;
import com.lasono.track.application.port.out.ProcessedAudio;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.Waveform;

/** Returns a fixed result, remembers the audio it was given, and can be told to fail. */
class FakeAudioProcessor implements AudioProcessor {

    static final byte[] MP3_BYTES = "converted mp3".getBytes(StandardCharsets.UTF_8);

    final List<byte[]> received = new ArrayList<>();
    ProcessedAudio result = new ProcessedAudio(
        new AudioDuration(180_000L), new Waveform(List.of(0.1f, 0.5f, 0.2f)), MP3_BYTES);
    RuntimeException failure;

    @Override
    public ProcessedAudio process(InputStream original) {
        try {
            received.add(original.readAllBytes());
        } catch (IOException e) {
            throw new AudioProcessingException("Failed to read the audio", e);
        }
        if (failure != null) {
            throw failure;
        }
        return result;
    }
}
