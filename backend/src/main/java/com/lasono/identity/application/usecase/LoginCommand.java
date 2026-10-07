package com.lasono.identity.application.usecase;

public record LoginCommand(
    String email,
    String password
) {

    // The generated toString() would print the password into any log line that mentions the command.
    @Override
    public String toString() {
        return "LoginCommand[email=" + email + ", password=***]";
    }
}
