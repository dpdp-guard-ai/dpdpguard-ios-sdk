# Audit-hash canonicalization spec

**Status:** Approved — see [`dpo-sign-off-request.md`](./dpo-sign-off-request.md)
item 1. Algorithm: **HMAC-SHA256** (the DPO's decision — a plain unkeyed hash
only proves the record wasn't altered after being written; the HMAC also
proves it was written by a party holding the platform's key).

This is the fixed, versioned canonicalization for the `consentAuditTrail.auditHash`
field, implemented in [`convex/lib/auditHash.ts`](../convex/lib/auditHash.ts) and
pinned by the golden vectors in
[`audit-hash-vectors.json`](./audit-hash-vectors.json). Any change to this
canonicalization or to the hash algorithm is a **major** contract-artifact
version bump under ADR-002 D4 and requires a fresh DPO sign-off, because it
breaks comparability of the immutable 7-year audit trail (spec §9).

## Key management

The HMAC key is read from the `DPDP_AUDIT_HASH_HMAC_SECRET` environment
variable (`convex/lib/auditHash.ts`'s `AUDIT_HASH_SECRET_ENV_VAR`).
`computeAuditHash` **throws** rather than falling back to an unkeyed hash if
it's unset — a misconfigured deployment must fail loudly on the first
consent write, not silently produce a weaker audit record. Provisioning the
production secret (`npx convex env set DPDP_AUDIT_HASH_HMAC_SECRET <value>`,
with real rotation/storage practices) is a deployment action outside this
repo; the test suite uses a fixed, clearly-labeled test-only value (set in
`vitest.setup.ts`, matching `audit-hash-vectors.json`'s `testSecret` field)
that must never be used in production.

## Input fields

| Field | Type | Notes |
|---|---|---|
| `organizationId` | string | |
| `noticeId` | string | |
| `noticeVersion` | integer | The version of the specific notice row consented to, not necessarily the org's current notice version. |
| `purpose` | string | |
| `dataTypes` | string[] | Sorted lexicographically before hashing — client-side ordering must not change the hash of an otherwise-identical event. |
| `givenAt` | integer | Unix epoch milliseconds. Client-authoritative per ADR-003 D3 (the moment the user acted, not when the write reached the server). |
| `source` | `"brokered" \| "direct" \| "anonymous" \| "linked" \| null` | ADR-004 D5 auth provenance. |

## Canonical form

```
organizationId|noticeId|noticeVersion|purpose|dataTypes(sorted,joined by ",")|givenAt|source("null" if absent)
```

Joined with `|`, then HMAC-SHA256'd against `DPDP_AUDIT_HASH_HMAC_SECRET` and
hex-encoded (lowercase).

## Why fields are never omitted

A missing field and an explicit `null` must hash differently from "the field
doesn't exist in this version of the algorithm" — so every field position is
always present in the joined string, using the literal `"null"` for an absent
`source`. This keeps a future *additive* field (new position appended at the
end) a minor change, while never producing an ambiguous canonical string for
today's fields.

## Golden vectors

See [`audit-hash-vectors.json`](./audit-hash-vectors.json) — fixed
input → expected canonical string → expected SHA-256 hash triples, asserted
by `convex/lib/auditHash.test.ts`. Any PR that changes a vector's expected
output must carry DPO sign-off in the PR description.
