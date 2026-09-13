package com.lasono.track.infrastructure.persistence;

import java.util.UUID;

import com.lasono.track.domain.model.TrackStatus;

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

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "description")
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private TrackStatus status;
}
