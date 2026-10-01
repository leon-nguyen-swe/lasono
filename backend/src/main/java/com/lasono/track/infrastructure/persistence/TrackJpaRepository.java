package com.lasono.track.infrastructure.persistence;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TrackJpaRepository extends JpaRepository<TrackJpaEntity, UUID> {
}
