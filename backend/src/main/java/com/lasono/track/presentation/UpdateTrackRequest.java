package com.lasono.track.presentation;

/** The body of a PATCH: a field that is left out stays as it is. To clear the description, send an empty one. */
public record UpdateTrackRequest(String title, String description, String visibility) {}
