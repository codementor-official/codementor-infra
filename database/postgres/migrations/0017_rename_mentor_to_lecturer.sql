-- 0017 — rename the platform role 'mentor' to 'lecturer'.
--
-- The product calls this role a lecturer everywhere it is visible: the frontend
-- application is apps/lecturer, the admin console lists "Lecturers", and the
-- Keycloak realm role is `lecturer`. Only the database still said `mentor`, so a
-- reader had to hold a translation in their head at every boundary.
--
-- ALTER TYPE ... RENAME VALUE rewrites the catalog entry only. No table is
-- rewritten and no row is touched, because an enum value is stored as an OID
-- rather than as text. It cannot run inside a multi-statement transaction block
-- in PostgreSQL versions before 12; this database is 18, where it can, so the
-- surrounding BEGIN/COMMIT is safe.

BEGIN;

ALTER TYPE platform_role RENAME VALUE 'mentor' TO 'lecturer';

COMMIT;
