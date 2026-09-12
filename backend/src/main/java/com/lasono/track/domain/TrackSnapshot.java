package com.lasono.track.domain;

import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioResourceStatus;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.model.TrackStatus;

public record TrackSnapshot(
    TrackId trackId,
    String title,
    String description,
    TrackStatus trackStatus,

    AudioResourceId audioResourceId,
    AudioResourceStatus audioResourceStatus,
    OriginalAudio originalAudio,
    StreamingAudio streamingAudio,
    AudioDuration audioDuration,
    Waveform waveform
) {}
