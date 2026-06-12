<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
`specs/001-hls-stream-validator/plan.md`

Active feature: 001-hls-stream-validator (HLS Stream Validator)
- Spec: specs/001-hls-stream-validator/spec.md
- Plan: specs/001-hls-stream-validator/plan.md
- Design: data-model.md, contracts/, research.md, quickstart.md (same directory)
- Stack: Swift 6 (strict concurrency), SwiftPM; deps: swift-argument-parser only
- Build/test: `swift build` / `swift test` — pipe through `xcsift` for log analysis

Implementation rules (binding):
- Code style: follow `styleguide.md` (repo root)
- Test code: follow `unit-testing.md` (repo root)
- Consult skills while implementing: `swift-testing-pro`, `swift-concurrency-pro`,
  `swift-api-design-guidelines`, `swift-architecture`, `swift-language`
- Integration tests use scripted in-process transport stubs — no local HTTP server
<!-- SPECKIT END -->
