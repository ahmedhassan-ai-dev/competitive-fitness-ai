# Proposed error contract extension — pending review

Status: proposal only, 2026-10-22. No wire models, OpenAPI artifacts or schemas
are changed. Existing v1 remains 1.0.0.

## Gap

ApiError currently permits unauthorized, forbidden, not_found, conflict and
validation_error, with a message of 1–100 characters. It cannot express server
faults or rate limits. The README's "all errors" statement exceeds what the enum
and OpenAPI can express. Relabeling 500 as conflict/validation_error is misleading.

## Proposed versioning

Treat new response enum values as breaking for strict consumers. Propose contract
2.0.0 in a parallel `packages/contracts/v2` and `/api/v2` API path. Do not silently
widen v1, add fields to its envelope, or emit new codes under /api/v1. If the team
instead chooses coordinated prerelease replacement or explicit negotiation, that
requires a separate owner-approved compatibility decision before implementation.

Proposed new responses (examples, not active schemas):

```json
{"code":"internal_error","message":"Internal server error."}
```

HTTP 500: unexpected internal failures only; no exception, SQL, credential or
stack-trace information. Operational logs must redact secrets. Do not mislabel
expected validation or authorization failures as 500.

```json
{"code":"rate_limited","message":"Too many requests. Try again later."}
```

HTTP 429: an actual enforced rate limit, with a positive integer Retry-After header
in seconds. Specify limits, trusted proxy/IP handling, identity/IP keys, distributed
enforcement and client backoff before introducing a limiter. No lockout policy is
introduced by this proposal. Retain the existing envelope and message length limit.

## Interim Checkpoint 1 behavior

Supported v1 errors consistently use ApiError. Unsupported 500/429 stay sanitized
plain text without adding enum values; clients must tolerate non-JSON transport
errors. Other unspecified HTTP statuses retain framework behavior. This interim
boundary is explicitly not full production error-contract readiness.

## Review gates

Mobile and Backend owners must approve version selection, rollout and fallback
handling, response schemas/statuses/headers, and contract tests. Decide separately
whether 503 service_unavailable and other transport statuses need coverage before
claiming a complete error envelope. Only then update models, generator, examples,
documentation and schemas together in a dedicated contract change. Authentication
success shapes and v1 endpoints must remain unchanged.
