package com.lasono.identity.domain;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

import com.lasono.identity.domain.exception.EmailAlreadyRegisteredException;

/**
 * Keeps users by email, like the unique constraint of the real table. {@link #size} is only for tests.
 */
public class InMemoryUserRepository implements UserRepository {

    private final Map<Email, User> store = new LinkedHashMap<>();

    @Override
    public User save(User user) {
        if (store.containsKey(user.getEmail())) {
            throw new EmailAlreadyRegisteredException(user.getEmail());
        }
        store.put(user.getEmail(), user);
        return user;
    }

    @Override
    public Optional<User> findByEmail(Email email) {
        return Optional.ofNullable(store.get(email));
    }

    @Override
    public Optional<User> findById(UserId id) {
        return store.values().stream().filter(user -> user.getId().equals(id)).findFirst();
    }

    public int size() {
        return store.size();
    }
}
