package com.lasono.identity.application.usecase;

import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;
import com.lasono.identity.domain.UserRepository;

@Component
public class UpdateProfileUseCase {

    private final UserRepository userRepository;

    public UpdateProfileUseCase(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public CurrentUserResult execute(UUID userId, String displayName) {
        // Checked first, with the same rules as registration, so a bad name is refused whatever the account.
        DisplayName newName = new DisplayName(displayName);

        User user = userRepository.findById(new UserId(userId)).orElseThrow(UserNotFoundException::new);
        user.changeDisplayName(newName);
        userRepository.save(user);

        return new CurrentUserResult(
            user.getId().getValue().toString(),
            user.getEmail().getValue(),
            user.getDisplayName().getValue()
        );
    }
}
