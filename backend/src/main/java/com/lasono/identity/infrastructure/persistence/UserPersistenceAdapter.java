package com.lasono.identity.infrastructure.persistence;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;

import org.hibernate.exception.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Repository;

import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;
import com.lasono.identity.domain.UserRepository;
import com.lasono.identity.domain.exception.EmailAlreadyRegisteredException;

@Repository
public class UserPersistenceAdapter implements UserRepository {

    // Name of the unique constraint on users.email in V4__create_users.sql.
    private static final String EMAIL_UNIQUE_CONSTRAINT = "uq_users_email";

    private final UserJpaRepository userJpaRepository;

    public UserPersistenceAdapter(UserJpaRepository userJpaRepository) {
        this.userJpaRepository = userJpaRepository;
    }

    @Override
    public User save(User user) {
        UserJpaEntity entity = new UserJpaEntity(
            user.getId().getValue(),
            user.getEmail().getValue(),
            user.getDisplayName().getValue(),
            user.getPasswordHash(),
            // PostgreSQL stores microseconds, so cut the nanoseconds to keep the value equal to the stored one.
            Instant.now().truncatedTo(ChronoUnit.MICROS)
        );

        try {
            // Flush so the INSERT runs here and a unique violation surfaces inside this method. Checking
            // "does the email exist?" first would not do: two sign-ups can both see "no" and both insert.
            userJpaRepository.saveAndFlush(entity);
        } catch (DataIntegrityViolationException e) {
            if (isTakenEmail(e)) {
                throw new EmailAlreadyRegisteredException(user.getEmail());
            }
            throw e;
        }

        return user;
    }

    @Override
    public Optional<User> findByEmail(Email email) {
        return userJpaRepository.findByEmail(email.getValue()).map(UserPersistenceAdapter::toDomain);
    }

    @Override
    public Optional<User> findById(UserId id) {
        return userJpaRepository.findById(id.getValue()).map(UserPersistenceAdapter::toDomain);
    }

    private static User toDomain(UserJpaEntity entity) {
        return new User(
            new UserId(entity.getId()),
            new Email(entity.getEmail()),
            new DisplayName(entity.getDisplayName()),
            entity.getPasswordHash()
        );
    }

    // Only the email constraint means "taken"; any other integrity error is a bug and must not be hidden.
    private static boolean isTakenEmail(Throwable error) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause instanceof ConstraintViolationException violation
                && EMAIL_UNIQUE_CONSTRAINT.equals(violation.getConstraintName())) {
                return true;
            }
        }
        return false;
    }
}
