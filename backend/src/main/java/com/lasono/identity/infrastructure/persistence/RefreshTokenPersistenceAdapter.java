package com.lasono.identity.infrastructure.persistence;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Repository;

import com.lasono.identity.domain.RefreshToken;
import com.lasono.identity.domain.RefreshTokenRepository;
import com.lasono.identity.domain.UserId;

@Repository
public class RefreshTokenPersistenceAdapter implements RefreshTokenRepository {

    private final RefreshTokenJpaRepository refreshTokenJpaRepository;

    public RefreshTokenPersistenceAdapter(RefreshTokenJpaRepository refreshTokenJpaRepository) {
        this.refreshTokenJpaRepository = refreshTokenJpaRepository;
    }

    @Override
    public void save(RefreshToken token) {
        // Flush so a problem such as a hash that is already taken shows up here and not later.
        refreshTokenJpaRepository.saveAndFlush(new RefreshTokenJpaEntity(
            token.getId(),
            token.getFamilyId(),
            token.getUserId().getValue(),
            token.getTokenHash(),
            token.getExpiresAt(),
            token.getUsedAt(),
            token.getRevokedAt()
        ));
    }

    @Override
    public Optional<RefreshToken> findByTokenHashForUpdate(String tokenHash) {
        return refreshTokenJpaRepository.findByTokenHash(tokenHash).map(RefreshTokenPersistenceAdapter::toDomain);
    }

    @Override
    public void revokeFamily(UUID familyId, Instant now) {
        refreshTokenJpaRepository.revokeFamily(familyId, now);
    }

    private static RefreshToken toDomain(RefreshTokenJpaEntity entity) {
        return RefreshToken.reconstitute(
            entity.getId(),
            entity.getFamilyId(),
            new UserId(entity.getUserId()),
            entity.getTokenHash(),
            entity.getExpiresAt(),
            entity.getUsedAt(),
            entity.getRevokedAt()
        );
    }
}
