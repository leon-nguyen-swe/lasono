package com.lasono.track.application.port.out;

import java.time.Instant;
import java.util.UUID;

import com.lasono.track.domain.model.TrackStatus;

/** The few fields of a track the list needs, without loading the whole track and its audio. */
public record TrackSummary(UUID id, String title, String description, TrackStatus status, Instant createdAt) {
}
