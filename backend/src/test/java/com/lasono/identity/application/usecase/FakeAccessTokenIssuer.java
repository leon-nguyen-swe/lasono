package com.lasono.identity.application.usecase;

import com.lasono.identity.application.port.out.AccessTokenIssuer;
import com.lasono.identity.application.port.out.IssuedAccessToken;
import com.lasono.identity.domain.UserId;

/** Hands out a readable fake token and counts how many were issued. */
public class FakeAccessTokenIssuer implements AccessTokenIssuer {

    public static final String PREFIX = "token-for-";
    public static final long LIFETIME_SECONDS = 900;

    private int calls;

    @Override
    public IssuedAccessToken issue(UserId userId) {
        calls++;
        return new IssuedAccessToken(PREFIX + userId.getValue(), LIFETIME_SECONDS);
    }

    public int calls() {
        return calls;
    }
}
