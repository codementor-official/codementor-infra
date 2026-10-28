## Summary

<!-- What changes, and why. Link the backend or frontend change this supports. -->

## Type of change

- [ ] PostgreSQL migration
- [ ] MongoDB schema
- [ ] Keycloak (realm, theme)
- [ ] Data host (Docker, scripts)
- [ ] Documentation

## Migration

<!-- File name, what it changes, and whether it is reversible. -->

- [ ] New numbered file; no applied migration edited
- [ ] Idempotent where possible and wrapped in a transaction
- [ ] `make database/reset && make database/verify` passes
- [ ] Production apply plan written below (order relative to the backend deploy)

<!-- Production apply plan: -->

## Host changes

- [ ] Verified on the host with `docker/scripts/verify-stack.sh`
- [ ] Listening addresses re-checked with `sudo ss -lntp` and match the README

## Checklist

- [ ] No secrets committed; new variables added to `.env.example`
- [ ] Documentation updated (schema reference regenerated if comments changed)
