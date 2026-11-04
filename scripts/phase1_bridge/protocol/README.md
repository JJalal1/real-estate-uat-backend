# Offline proposal: same-job Root review protocol

This is a tested protocol component, not an integrated GitHub workflow or a
native acceptance result. No device, account, network service, real task key or
credential is used by the implementation or its tests. It was developed with
Python 3.12 and the already-installed `cryptography==50.0.2`; it adds no product
dependency. It targets a Linux CI owner and local filesystem with working flock.

## Trust and lifecycle

One owner keeps the VM, fixture identity, actor credentials and job X25519
private key within the same live job. `JobEphemeralKey.public()` exports only the
32-byte public component. `close()` drops its private-key reference; neither
Python garbage collection nor this code establishes secure memory erasure.
Never serialize the private component, auth state, app storage or an AVD.

The owner creates an immutable encrypted checkpoint with its job public key,
source/tool hashes, run and attempt, sequence, cursor, random 32-byte challenge,
previous result digest and actual reviewed-frame manifest. Root downloads that
artifact from the verified source/run, checks its digest and personally reviews
the actual frames. The checkpoint ciphertext SHA256 becomes `cipher_sha`.

Root's separate Ed25519 signing public key must be pinned in the reviewed job
source. Never obtain that trust anchor from the command branch. Root's signing
private key never enters CI. Root uses `build_command` with the actual completed
review record and the authenticated job public key. This function does not
create review flags, perform image review or grant acceptance.

Root publishes the resulting public envelope through its existing repository
connector. The job polls only a fixed branch/path for its own run/attempt/seq
with a read-only GitHub token. It never checks out or executes that branch.
Networking, artifact ownership and producer identity are integration duties;
this module deliberately has no network or environment reads.

## Envelope contract

The only keys are:

```
version repo run_id run_attempt source_sha toolbundle_sha seq phase cursor
checkpoint_challenge cipher_sha prev_result_sha op issued_utc expires_utc
root_key_id encrypted_review_b64 signature
```

`version` is integer 1. Repository is exactly
`JJalal1/real-estate-uat-backend`; run ID is an ASCII positive decimal string.
Attempt and sequence are positive JSON integers, never booleans or floats.
Source SHA is 40 lowercase hex characters. Tool, challenge, checkpoint, previous
result and root-key digests are 64 lowercase hex characters. Cursors use bounded
uppercase identifiers; phase is C1, C4, C2 or C5. Operations are only `advance`,
`reject`, `finish`. Metadata is compared to a `Context` produced by the trusted
owner from its held state, not by copying fields from the received envelope.

UTC timestamps use exact `YYYY-MM-DDTHH:MM:SSZ`. Signed TTL is positive and at
most 120 seconds; at most five seconds of future clock skew is permitted.
Commands are rejected after expiry. UTC validation is followed by a monotonic
remaining-time guard that includes signature/decryption, durable reservation
and scene-check time. Entry into dispatch is rechecked after the scene callback.

Canonical bytes use UTF-8, sorted keys, compact separators and no NaN/Infinity.
All JSON objects reject duplicate keys, including duplicates after JSON string
decoding. Envelope size is at most 48 KiB. Ed25519 signs a versioned domain plus
the entire canonical envelope except `signature`.

Review encryption is ephemeral sender X25519, random 32-byte HKDF-SHA256 salt,
a derived 256-bit AES-GCM key and random 12-byte nonce. A versioned KDF domain
and metadata digest bind key derivation. All stable envelope metadata is AEAD
associated data. Signature binds that metadata and the complete encrypted
review. `cipher_sha` identifies the checkpoint, not the encrypted-review bytes,
so there is no ciphertext/AAD circularity. Binary review format is fixed magic,
sender public key (32), salt (32), nonce (12), ciphertext and full GCM tag.

## Actual review and privacy

Decrypted review is an operator-provided JSON object, bounded to 16 KiB,
10 levels, 512 values and 4096 characters per string. Keys are bounded ASCII
identifiers. Authentication-key segments and complete phone-shaped strings are
refused. The owner must additionally pass all currently known private actor,
OTP and token aliases in memory as `forbidden_values`. The default empty list
does not establish that unknown credential values are absent. No such aliases
are read, discovered, serialized or logged by this module.

Review values support strings, bounded integers, booleans, null, lists and
objects. Floats are deliberately refused. Existing local review schemas are
therefore **not drop-in compatible**: fractional video duration needs an explicit
milliseconds integer or exact decimal-string adaptation; the old local
`reviewed_monotonic` field needs a reviewed remote-freshness schema. Do not round
or fabricate a duration, and never set `reviewed_monotonic = now` to impersonate
Root review. Preserve actual signed Root review UTC, job receipt time, frame
hashes, held checkpoint identity and a fresh actual scene comparison.

Validated review bytes are immutable internally and omitted from object repr.
Each scene/dispatch callback receives a separate parsed copy; a scene checker
cannot add approval flags to the record passed to dispatch. The protocol never
invents `accepted`, `review_completed`, timestamps, actor identities or facts.
Existing phase-specific validators must still approve the exact Root record.
No review, exception payload, credentials or cryptographic inputs are printed.
An owner must also suppress raw callback/BaseException logging in its outer
cleanup handler; ordinary callback exceptions become fixed diagnostic codes.

## One command, one attempt

`receive` holds a nonblocking thread lock and directory flock for the entire
verify/reserve/scene/dispatch transaction. Distinct sequences cannot overlap,
including through a second ledger object or process. Close the ledger only
after receive is quiescent and no callback is active.

The ledger path is a fixed owner-selected absolute path. Every path component is
opened relative to its parent descriptor with `O_NOFOLLOW`; only the final
directory may be created, owned by the current actor with mode 0700. Entries
must be single-link regular owned files with mode 0600. No symlink, hardlink,
unexpected entry, broad permissions, partial record, sequence gap or orphan
outcome is adopted. The consume record is created with `O_EXCL`, fully written
and fsynced along with its directory **before** a scene callback or dispatch.
Ledger records contain only fixed statuses and command/context/session digests.

Reservation session identity also binds repository, run/attempt, source, tool
bundle, Root public-key ID and ephemeral job public-key digest. A different job,
attempt, source, tool bundle or key cannot reuse the ledger chain.

Dispatch returns literal `True` only after its actual postcondition is observed.
False, None, truthy substitutes, exceptions and interrupted execution are
uncertain and remain consumed. A missing outcome after process loss also
remains consumed. No later `advance` follows an uncertain previous operation;
only `finish` or `reject` can close. Both close operations are terminal regardless
of whether their cleanup succeeded. A close cannot clear the latch and enable
another advance. Cleanup uncertainty is reported, not repaired by a replay.

An exact duplicate canonical signed envelope returns `already_consumed` without
another callback, provided its context/signature/decryption/TTL are still valid.
Expired duplicates are refused; refusal does not establish that the original
operation never ran. Rebuilding a command generates fresh encryption and thus a
different command digest; a newly signed same-sequence payload is not a retry.

## Remaining integration requirements

- Bind the public key/checkpoint to the exact verified CI source and run.
- Validate actual phase-specific Root review fields and fresh scene before input.
- Enforce the signed command deadline immediately before **every UI mutation**
  within a multi-input segment; this protocol guards dispatch entry only. Always
  release a pointer already pressed even when a deadline expires.
- Keep `reject`/`finish` dispatch limited to the reviewed bounded close/cleanup
  path. Owner timeout and signal cleanup must run independently of Root commands.
- Preserve original fixture UUID/tag/baseline, stop native writers, and use the
  strict Property-first promoted cleaner when C2 has created a Property.
- Reserve cleanup time before job timeout and retain an encrypted fixture-only
  pre-mutation checkpoint for strict later cleanup after abrupt runner loss.
- Never treat this protocol receipt or its tests as actual Android acceptance.

Run offline tests with:

```
python3 -B -m unittest -v test_review_protocol.py
```

Official API references:

- https://cryptography.io/en/stable/hazmat/primitives/asymmetric/ed25519/
- https://cryptography.io/en/stable/hazmat/primitives/asymmetric/x25519/
- https://cryptography.io/en/stable/hazmat/primitives/aead/
