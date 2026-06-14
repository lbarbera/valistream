# Feature 004 acceptance inputs

On 2026-06-14 the user supplied two conversation-only HLS acceptance inputs:
- Live channel label: TV Nord
- Video-on-demand label: NRK news

Do NOT store or reproduce the URLs in repository files or project memory. Retrieve them from the conversation only when running manual acceptance. Their query strings include account metadata, client IP, timestamps, opaque authorization-like values, and (for VOD) a fixed playback window, so treat them as sensitive and potentially expiring even though the user says no separate credentials are required.

Use both to validate feature 004 terminal readability and README examples. Any committed examples must use sanitized URLs and output.