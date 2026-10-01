package com.lasono.track.infrastructure.persistence;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface AudioResourceJpaRepository extends JpaRepository<AudioResourceJpaEntity, UUID> {  
    Optional<AudioResourceJpaEntity> findByTrack_Id(UUID trackId); 
}