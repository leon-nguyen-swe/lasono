package com.lasono.track.application.port.out;

import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.Waveform;

/** What processing an uploaded audio file produces: its length, its shape, and the MP3 to stream. */
public record ProcessedAudio(AudioDuration duration, Waveform waveform, byte[] streamingAudio) {}
