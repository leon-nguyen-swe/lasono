package com.lasono.identity.application.usecase;

import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.identity.application.port.out.AccessTokenIssuer;
import com.lasono.identity.application.port.out.IssuedAccessToken;
import com.lasono.identity.application.port.out.PasswordHasher;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserRepository;
import com.lasono.identity.domain.exception.EmailInvalidException;

@Component
public class LoginUseCase {

    private static final String TOKEN_TYPE = "Bearer";

    private final UserRepository userRepository;
    private final PasswordHasher passwordHasher;
    private final AccessTokenIssuer accessTokenIssuer;
    private final String unknownUserHash;

    public LoginUseCase(
        UserRepository userRepository,
        PasswordHasher passwordHasher,
        AccessTokenIssuer accessTokenIssuer
    ) {
        this.userRepository = userRepository;
        this.passwordHasher = passwordHasher;
        this.accessTokenIssuer = accessTokenIssuer;
        // The hash of a password nobody knows, made once. It is what an unknown email is compared against.
        this.unknownUserHash = passwordHasher.hash(UUID.randomUUID().toString());
    }

    public LoginResult execute(LoginCommand command) {
        Optional<User> user = findUser(command.email());

        // Always compare exactly one password, even for an unknown email. Comparing is slow on purpose, so
        // skipping it would make "no such email" answer faster and let a stranger find out which emails exist.
        String hash = user.map(User::getPasswordHash).orElse(unknownUserHash);
        boolean passwordMatches = passwordHasher.matches(command.password(), hash);

        if (user.isEmpty() || !passwordMatches) {
            throw new InvalidCredentialsException();
        }

        IssuedAccessToken token = accessTokenIssuer.issue(user.get().getId());
        return new LoginResult(token.value(), TOKEN_TYPE, token.expiresInSeconds());
    }

    // An email that is not even valid is just another email nobody has registered.
    private Optional<User> findUser(String email) {
        try {
            return userRepository.findByEmail(new Email(email));
        } catch (EmailInvalidException e) {
            return Optional.empty();
        }
    }
}
