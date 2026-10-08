package com.lasono.identity.application.port.out;

import com.lasono.identity.domain.UserId;

public interface AccessTokenIssuer {

    /** Creates a short-lived signed token that says "this request comes from this user". */
    IssuedAccessToken issue(UserId userId);
}
