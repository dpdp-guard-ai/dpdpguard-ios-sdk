# Audit-hash canonicalization spec

**Algorithm:** HMAC-SHA256 — a plain unkeyed hash only proves the record
wasn't altered after being written; the HMAC also proves it was written by
a party holding the platform's key.

This is the fixed, versioned canonicalization for the
`consentAuditTrail.auditHash` field, pinned by the golden vectors in
[`audit-hash-vectors.json`](./audit-hash-vectors.json). Any change to this
canonicalization or to the hash algorithm is a **major** version bump for
this package, since it breaks comparability of the immutable, long-retained
audit trail.

## Key management

The HMAC key is provisioned server-side and never leaves DPDP Guard's
infrastructure. Hash computation fails loudly (rather than falling back to
an unkeyed hash) if the key is unconfigured — a misconfigured deployment
must surface immediately, not silently produce a weaker audit record.

### Key versions

Every hash is written with the id of the key version that produced it, stored
in `consentAuditTrail.auditHashKeyId`. Verification re-derives under *that*
id rather than under whatever the current default is, so rotating the key
does not retroactively invalidate rows written before it. A row with no
stored id predates key ids and is read as `v1`.

The registry lives in `convex/lib/crypto.ts`:

| Key id | Derivation | Status |
|---|---|---|
| `v1` | The root secret is used directly for every purpose. | **Default.** What the golden vectors below pin, and what every row written before key ids used. |
| `v2` | HKDF-SHA256 over the same root, `info = "dpdpbot/<purpose>/v2"`, giving each purpose a distinct subkey. | Implemented and tested, **not active**. |

`v1` uses one key for three unrelated jobs — the audit hash, the offline
capture countersignature, and the `phone_hash` principal-handle
pseudonymisation. Those have different threat models: the handle key is a
confidentiality control over personal data (the Indian mobile space is ~10⁹
candidates, so a leaked key means re-identification across every fiduciary),
while the audit key is an integrity control. `v2` separates them.

### Activating `v2` is a breaking change

Switching `DEFAULT_KEY_ID` changes the bytes this algorithm produces. Under
ADR-002 D4 that is a **major** version bump requiring fresh DPO sign-off,
because it breaks comparability of the immutable trail. It is not a
refactor and must not be done as part of one. Existing rows remain verifiable
under `v1` regardless; the golden vectors below continue to describe `v1`.

One consequence to plan for separately: the principal-handle key cannot be
rotated without loss. A handle is a lookup index and the raw phone number is
deliberately never stored, so stored handles cannot be re-derived under a new
key. Rotating it costs linkability for every existing handle unless callers
dual-read across key ids.

## Input fields

| Field | Type | Notes |
|---|---|---|
| `organizationId` | string | |
| `noticeId` | string | |
| `noticeVersion` | integer | The version of the specific notice row consented to, not necessarily the org's current notice version. |
| `purpose` | string | |
| `dataTypes` | string[] | Sorted lexicographically before hashing — client-side ordering must not change the hash of an otherwise-identical event. |
| `givenAt` | integer | Unix epoch milliseconds — the moment the user acted, not when the write reached the server. |
| `source` | `"brokered" \| "direct" \| "anonymous" \| "linked" \| null` | Auth provenance of how the consent was captured. |

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
input → expected canonical string → expected SHA-256 hash triples. Use
these to verify an independent implementation of this algorithm produces
identical output. A test-only HMAC secret is included (`testSecret`) for
reproducing these vectors — never use it in production.

---

# Cryptographic Consent Artifact (offline capture)

`convex/lib/captureArtifact.ts` — the signature an *enrolled device* produces
for a consent captured away from the network
(`docs/specs/offline-consent-capture.md` §4.2).

## Why this is a second algorithm, not a replacement

The audit hash above is an HMAC keyed by the platform's own secret. It proves
a record is unaltered and was written by the platform — but because the
platform holds the key, it cannot prove the platform did not fabricate the
record, and it says nothing about *which* agent, on which device, at which
branch captured the consent. The CCA closes exactly that gap: the signing key
is generated in the device's secure element, never leaves it, and is never
transmitted, so a verifying signature can only have been produced by that
enrolled device. A DPBI defence needs both properties; both are stored, on the
`consentAuditTrail` row and the `offlineCaptureSessions` row respectively.

## Fields

| Field | Type | Notes |
|---|---|---|
| `clientSessionId` | string | Client-generated UUIDv4; also the sync idempotency key. |
| `organizationId` | string | |
| `deviceId` | string | The `agentDevices` row whose public key must verify this signature. |
| `noticeId` | string | |
| `noticeVersion` | integer | Verified against the notice's *current* version at sync; a superseded version quarantines. |
| `noticeLocale` | string | Eighth Schedule locale actually rendered — s. 5(3) evidence, inside the signature. |
| `purposeGrants` | `{purposeKey, status}[]` | A count token, then `purposeKey` and `status` per grant, sorted by `purposeKey`. Duplicate keys are rejected at sync, never collapsed. |
| `dataTypes` | string[] | A count token, then the values, sorted. |
| `principalHandleKind` | `"phone_hash" \| "uhid" \| "cbs_ref" \| "none"` | |
| `principalHandleValue` | string | The **raw** handle as collected. Signed raw so an SDK need not reimplement the platform's HMAC; the row stores the hash, and the canonical string is persisted beside it so the signature stays re-verifiable. `"null"` when empty. |
| `capturedAtClient` | integer | Device clock. Context, never authority — see clock trust below. |
| `channel` | `"qr" \| "agent_app" \| "pos" \| "async_link" \| "ivr"` | |

## Canonical form

Every token is framed as `<utf8ByteLength>:<value>`, and the tokens are joined
with `|`:

```
version | clientSessionId | organizationId | deviceId | noticeId
  | noticeVersion | noticeLocale
  | grantCount | (purposeKey, status) per grant, sorted by purposeKey
  | dataTypeCount | dataType per entry, sorted
  | principalHandleKind | principalHandleValue ("null" if empty)
  | capturedAtClient | channel
```

`version` is the literal `dpdpcca/2` and is the first token of every canonical
string. No whitespace anywhere; the line breaks above are for readability only.
A worked example, from the first golden vector:

```
9:dpdpcca/2|36:11111111-2222-3333-4444-555555555555|10:org_abc123|15:device_pune_114|9:notice_v3|1:3|2:hi|1:1|16:kyc_verification|6:opt_in|1:1|3:pan|10:phone_hash|10:9876543210|13:1700000000000|9:agent_app
```

The UTF-8 bytes of that string are signed with **ECDSA P-256 / SHA-256**; the
signature is the raw IEEE-P1363 `r||s` pair, base64-encoded. The public key is
base64 SPKI DER, exactly as stored on `agentDevices`.

Three rules an SDK must get exactly right, each pinned by a golden vector:

- **Length is counted in UTF-8 bytes** — not characters, not UTF-16 units.
  `विपणन` is five characters and frames as `15:विपणन`.
- **Sorts are byte-wise over UTF-8**, not the platform's default string
  comparison; Swift's default compares grapheme clusters and would disagree.
  The sorts are load-bearing: without them, a client that happened to list its
  purposes in a different order on retry would produce a different canonical
  string and quarantine a legitimate consent as `signature_mismatch`.
- **Lists carry an explicit count and every element is framed.** This is what
  `dpdpcca/1` lacked, and why it was replaced before any SDK shipped against
  it: with elements merely joined by `,`, a single purpose named
  `kyc:opt_out,marketing` produced byte-identical output to a two-purpose
  capture that had *declined* KYC. `purposeKey` and `dataTypes` are
  client-supplied, so one device signature attested to two materially different
  consent payloads — destroying the non-repudiation property this algorithm
  exists to provide. Vectors "separator injection A/B" pin that the two now
  differ.

Changing this encoding again requires bumping the version token: a stored
signature can only be verified under the encoding in force when it was made.

## Platform countersignature

After verification the server writes `HMAC-SHA256(<canonical>|<syncedAtServer>)`,
hex-encoded, keyed by the same `DPDP_AUDIT_HASH_HMAC_SECRET`. It attests to
something the device cannot: when the platform first saw the capture.

## Clock trust

`capturedAtClient` is recorded verbatim and never used for arithmetic.
`syncedAtServer` is authoritative for retention windows and breach deadlines.
Skew beyond **7 days** in either direction quarantines the session for DPO
review — field devices genuinely go a week without connectivity; a month means
the clock is wrong or the capture is backdated.

## Golden vectors

See [`capture-artifact-vectors.json`](./capture-artifact-vectors.json). Device
signatures are ECDSA and therefore non-deterministic, so the vectors pin the
canonical string and the (deterministic) countersignature; an SDK proves
compatibility by reproducing `expectedCanonical` byte-for-byte.

## Changing any of this

Altering the canonicalisation, the field order, or the algorithm is a
**breaking change** under ADR-002 D4 and invalidates every stored signature —
the same standing as the audit-hash algorithm above, and it requires the same
DPO sign-off.
