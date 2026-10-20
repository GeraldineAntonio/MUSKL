CREATE TABLE social_identities (
    provider text NOT NULL CHECK (provider IN ('google', 'apple')),
    subject text NOT NULL,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject),
    UNIQUE (provider, user_id)
);

CREATE INDEX social_identities_user_id_idx ON social_identities(user_id);
