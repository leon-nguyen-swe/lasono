package com.lasono.track.domain;

import java.util.UUID;

/** Values shared by the tests of the track module. */
public final class TrackFixtures {

    /** Any owner will do for a test that is not about ownership. */
    public static final OwnerId OWNER = new OwnerId(UUID.fromString("00000000-0000-0000-0000-0000000000a1"));

    private TrackFixtures() {
    }
}
