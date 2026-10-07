package com.lasono.track.application.port.out;

import java.io.InputStream;

public interface AudioProcessor {

    /**
     * Reads the length of the audio, builds its waveform and converts it to the streaming format (MP3).
     *
     * @throws AudioProcessingException if the audio is corrupt or the conversion fails
     */
    ProcessedAudio process(InputStream original);
}
