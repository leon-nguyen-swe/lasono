package com.lasono.identity.domain;

/** What a refresh token may be used for at a given moment. */
public enum RefreshTokenCheck {
    USABLE,
    EXPIRED,
    REVOKED,
    /** Already exchanged once. Showing it again means somebody holds a copy of it. */
    ALREADY_USED
}
