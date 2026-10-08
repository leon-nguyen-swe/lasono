-- Every track now has an owner. There is no foreign key to users: modules do not reference each other's
-- tables, the track module only holds the id of the owner.
ALTER TABLE tracks
    ADD COLUMN owner_id UUID;

-- Tracks uploaded before accounts existed have no owner. They go to one placeholder user, and only when there
-- are such tracks, so a new database does not get a user nobody asked for. Nobody can log in as it: the password
-- hash '!' is not a valid BCrypt hash, so no password matches it. The email uses the reserved ".invalid" domain.
INSERT INTO users (id, email, display_name, password_hash)
SELECT '00000000-0000-0000-0000-00000000001e', 'legacy@lasono.invalid', 'Legacy', '!'
WHERE EXISTS (SELECT 1 FROM tracks);

UPDATE tracks
SET owner_id = '00000000-0000-0000-0000-00000000001e';

ALTER TABLE tracks
    ALTER COLUMN owner_id SET NOT NULL;
