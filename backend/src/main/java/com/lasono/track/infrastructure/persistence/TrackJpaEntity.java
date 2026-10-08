package com.lasono.track.infrastructure.persistence;

import java.time.Instant;
import java.util.UUID;

import com.lasono.track.domain.model.TrackStatus;
import com.lasono.track.domain.model.Visibility;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter 
@NoArgsConstructor(access = AccessLevel.PROTECTED) 
@AllArgsConstructor
@Entity 
@Table(name = "tracks")
public class TrackJpaEntity {

    @Id
    private UUID id;

    // The id of a user. No foreign key: the track module does not reference the tables of identity.
    // updatable = false because a track never changes hands.
    @Column(name = "owner_id", nullable = false, updatable = false)
    private UUID ownerId;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "description")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(name = "visibility", nullable = false)
    private Visibility visibility;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private TrackStatus status;

    // updatable = false keeps the original value when the same track is saved again.
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
}
