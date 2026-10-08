-- Refresh tokens of the identity module. A token is never stored itself, only the SHA-256 hash of it
-- (64 hex characters), so a leaked copy of this table cannot be used to log in.
-- family_id groups all tokens that come from one login. Each exchange replaces a token by a new one in the
-- same family; if a token that was already used shows up again, the whole family is revoked.
CREATE TABLE refresh_tokens
(
    id UUID NOT NULL,
    family_id UUID NOT NULL,
    user_id UUID NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_refresh_tokens PRIMARY KEY (id),
    -- A token is looked up by its hash.
    CONSTRAINT uq_refresh_tokens_hash UNIQUE (token_hash),
    -- Same module as users, so a foreign key is fine. A deleted account takes its sessions with it.
    CONSTRAINT fk_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Revoking a family finds all its tokens.
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens (family_id);
