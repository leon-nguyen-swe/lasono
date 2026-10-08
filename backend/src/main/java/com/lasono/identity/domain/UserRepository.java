package com.lasono.identity.domain;

import java.util.Optional;

public interface UserRepository {

    /**
     * Saves a user. A user with the same id is replaced, so this also stores a change.
     *
     * @throws com.lasono.identity.domain.exception.EmailAlreadyRegisteredException if another user
     *         already has the same email
     */
    User save(User user);

    Optional<User> findByEmail(Email email);

    Optional<User> findById(UserId id);
}
