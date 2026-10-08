package com.lasono.track.application.usecase;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.StreamUrlSigner;
import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;

@Component
public class GetStreamUrlUseCase {

    private final TrackRepository trackRepository;
    private final StreamUrlSigner signer;
    private final Clock clock;
    private final Duration timeToLive;

    public GetStreamUrlUseCase(
        TrackRepository trackRepository,
        StreamUrlSigner signer,
        Clock clock,
        @Value("${lasono.stream.url-ttl:1h}") Duration timeToLive
    ) {
        this.trackRepository = trackRepository;
        this.signer = signer;
        this.clock = clock;
        this.timeToLive = timeToLive;
    }

    public StreamUrlResult execute(UUID trackId, UUID viewerId) {
        // Only someone who may see the track gets a signature for it, or the signature would be a way in.
        trackRepository.findById(new TrackId(trackId))
            .filter(found -> found.isVisibleTo(viewerId == null ? null : new OwnerId(viewerId)))
            .orElseThrow(() -> new TrackNotFoundException(trackId));

        Instant expiresAt = clock.instant().plus(timeToLive);
        long expires = expiresAt.getEpochSecond();
        String signature = signer.sign(trackId, expires);

        return new StreamUrlResult(
            "/api/v1/tracks/" + trackId + "/stream?expires=" + expires + "&signature=" + signature,
            expiresAt
        );
    }
}
