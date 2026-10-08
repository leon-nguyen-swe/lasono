package com.lasono.identity.domain;

public interface UserRepository {

    /**
     * Saves a new user.
     *
     * @throws com.lasono.identity.domain.exception.EmailAlreadyRegisteredException if another user
     *         already has the same email
     */
    User save(User user);
}
