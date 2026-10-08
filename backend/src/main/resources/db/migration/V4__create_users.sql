-- Accounts of the identity module. No other table has a foreign key to it: modules do not reference
-- each other's tables, they hold the user id as a plain value.
CREATE TABLE users
(
    id UUID NOT NULL,
    email VARCHAR(254) NOT NULL,
    display_name VARCHAR(50) NOT NULL,
    -- BCrypt hashes are 60 characters; the rest leaves room for another algorithm later.
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_users PRIMARY KEY (id),
    -- The code recognises a taken email by the name of this constraint.
    CONSTRAINT uq_users_email UNIQUE (email),
    -- The domain lowercases emails. This keeps a direct INSERT from creating Alice@x.com next to alice@x.com.
    CONSTRAINT ck_users_email_lowercase CHECK (email = lower(email))
);
