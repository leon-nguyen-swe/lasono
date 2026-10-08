package com.lasono.track.application.usecase;

import java.util.UUID;

/** A field that is null stays as it is. To clear the description, send an empty one. */
public record UpdateTrackCommand(
    UUID trackId,
    UUID requesterId,
    String title,
    String description,
    String visibility
) {}
