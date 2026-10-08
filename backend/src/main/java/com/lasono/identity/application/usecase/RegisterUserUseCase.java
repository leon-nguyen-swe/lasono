package com.lasono.identity.application.usecase;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.identity.application.port.out.PasswordHasher;
import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;
import com.lasono.identity.domain.UserRepository;

@Component
public class RegisterUserUseCase {

    private static final int MIN_PASSWORD_LENGTH = 8;

    // BCrypt only reads the first 72 bytes of a password and silently ignores the rest.
    private static final int MAX_PASSWORD_BYTES = 72;

    private final UserRepository userRepository;
    private final PasswordHasher passwordHasher;

    public RegisterUserUseCase(UserRepository userRepository, PasswordHasher passwordHasher) {
        this.userRepository = userRepository;
        this.passwordHasher = passwordHasher;
    }

    public RegisterUserResult execute(RegisterUserCommand command) {
        // Cheap checks first: hashing is slow on purpose, so it only runs for input that is valid.
        Email email = new Email(command.email());
        DisplayName displayName = new DisplayName(command.displayName());
        validatePassword(command.password());

        User user = new User(
            new UserId(UUID.randomUUID()),
            email,
            displayName,
            passwordHasher.hash(command.password())
        );
        userRepository.save(user);

        return new RegisterUserResult(
            user.getId().getValue().toString(),
            email.getValue(),
            displayName.getValue()
        );
    }

    private static void validatePassword(String password) {
        if (password == null || password.isBlank()) {
            throw new PasswordInvalidException("Password must not be blank");
        }
        if (password.length() < MIN_PASSWORD_LENGTH) {
            throw new PasswordInvalidException("Password must be at least " + MIN_PASSWORD_LENGTH + " characters");
        }
        if (password.getBytes(StandardCharsets.UTF_8).length > MAX_PASSWORD_BYTES) {
            throw new PasswordInvalidException("Password must be at most " + MAX_PASSWORD_BYTES + " bytes");
        }
    }
}
