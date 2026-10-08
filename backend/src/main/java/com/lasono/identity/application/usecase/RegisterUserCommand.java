package com.lasono.identity.application.usecase;

public record RegisterUserCommand(
    String email,
    String displayName,
    String password
) {

    // The generated toString() would print the password into any log line that mentions the command.
    @Override
    public String toString() {
        return "RegisterUserCommand[email=" + email + ", displayName=" + displayName + ", password=***]";
    }
}
