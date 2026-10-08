package com.lasono.identity.application.usecase;

import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;
import com.lasono.identity.domain.UserRepository;

@Component
public class GetProfileUseCase {

    private final UserRepository userRepository;

    public GetProfileUseCase(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public ProfileResult execute(UUID userId) {
        User user = userRepository.findById(new UserId(userId))
            .orElseThrow(() -> new ProfileNotFoundException(userId));

        // Only what anyone may see. The email stays with its owner (see GetCurrentUserUseCase).
        return new ProfileResult(user.getId().getValue().toString(), user.getDisplayName().getValue());
    }
}
