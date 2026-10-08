package com.lasono.identity.application.usecase;

import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;
import com.lasono.identity.domain.UserRepository;

@Component
public class GetCurrentUserUseCase {

    private final UserRepository userRepository;

    public GetCurrentUserUseCase(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public CurrentUserResult execute(String userId) {
        User user = parse(userId)
            .flatMap(userRepository::findById)
            .orElseThrow(UserNotFoundException::new);

        return new CurrentUserResult(
            user.getId().getValue().toString(),
            user.getEmail().getValue(),
            user.getDisplayName().getValue()
        );
    }

    // The id comes from a token we signed, but a value that is not a UUID is still just "no such user".
    private static Optional<UserId> parse(String userId) {
        if (userId == null) {
            return Optional.empty();
        }
        try {
            return Optional.of(new UserId(UUID.fromString(userId)));
        } catch (IllegalArgumentException e) {
            return Optional.empty();
        }
    }
}
