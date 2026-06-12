# Unit testing conventions

Module-agnostic baseline for **unit** test suites across Swift packages

---

## 1. Scope

**In scope:** unit tests for any module — business logic, model invariants, query construction, aggregation, pure-Swift utilities.

**Out of scope (separate specs / tickets):**

- UI, snapshot, XCUITest suites.
- Schema-migration and performance tests.
- Cross-module integration tests.

## 2. Runtime

**Swift Testing only.** No XCTest in new code: no `XCTestCase`, no `XCTAssert*`, no `XCTUnwrap`. Use `@Test`, `@Suite`, `#expect`, `#require`, traits, tags, parameterized `arguments:`. Drive runner through **xcode-tools** (`BuildProject`, `GetTestList`, `RunAllTests`, `RunSomeTests`) against module scheme's test plan (`source/TestPlans/<Module>.xctestplan`). `iOS` scheme's plan aggregates every module's unit tests, so app CI exercises them too.

## 3. Folder and file conventions

Test files mirror module's source layout — **one test file per source file** — under `<Module>Tests/`, grouped into flat by-category folders matching source tree:

```
<Module>Tests/
├── _setup/                              # shared infra; set up once, never grows per feature
│   ├── <Module>TestEnvironment.swift    # only if the module needs a per-test backing store
│   ├── TestContainerSetup.swift         # only if the module resolves DI through a container
│   ├── Tags.swift
│   ├── Fixtures/<Type>+Fixture.swift    # one per persisted/model type
│   ├── Scenes/                          # composite builders for multi-level trees
│   └── Verifications/                   # shared assertion / query helpers used by >1 file
└── <Category>/<Name>Tests.swift         # mirrors <Name>.swift in the module's source
```

- `_setup/` underscore-prefixed → sorts to top.
- Test for method goes in file mirroring **source file the method lives in**. Type split across files (e.g. base + extension): follow actual symbol's file; if unsure, default to primary (non-extension) file.

## 4. Suite structure

- Suite = `struct`; `@Suite` required only to attach traits or display name (struct with `@Test` methods = auto-suite).
- Per-test state built in `init() throws`. Swift Testing has **no** `setUp`/`tearDown`; per-test resources released when struct dropped after test.
- **`@MainActor` only when needed.** Annotate suite `@MainActor` when touching main-actor-isolated state (e.g. SwiftData `ModelContext`). Pure-logic suites stay non-isolated, parallelize freely — don't add `@MainActor` by reflex.
- Large files use **nested `@Suite` per behavior** instead of splitting source file. Each nested suite = own struct with own state, inherits parent's traits.

```swift
@Suite(.tags(.area))
struct ExampleTests {
    @Test("does the thing")
    func doesTheThing() throws { /* ... */ }
}
```

## 5. Test naming

- `@Test("…")` display name: short behavior sentence, no "should", under ~80 chars.
- Function name camelCase, restates behavior (readable reports without raw-identifier surprises).
- Nested-suite display names = method or behavior under test, e.g. `@Suite("createWorkout(from:)")`.

## 6. Assertion rules

- One behavior per test; multiple `#expect`s fine.
- Preconditions / unwraps use `try #require(...)` — **never** force-unwrap (`!`) in test body.
- Negate with `== false`, **never** `#expect(!flag)`.
- Expected throws: `#expect(throws: SpecificError.self)` — never `Error.self`.
- Float comparisons use absolute tolerance:

```swift
#expect(abs(value - expected) < 0.0001)
```

## 7. Parameterized tests

Prefer `arguments:` over copy-pasted tests. Keep argument data lean, zip inputs to expectations:

```swift
@Test("warmUp count clamps to bounds", arguments: zip([-1, 0, 1, 2, 10], [0, 0, 1, 2, 3]))
func warmUpCountClampsToBounds(input: Int, expected: Int) throws { /* ... */ }
```

## 8. Traits

- **`.tags(_:)`** — orthogonal filters from module's `Tags.swift` (see §13).
- **`.bug(_:)`** — link test to tracking issue when reproducing known bug.
- **`.timeLimit(.minutes(_:))`** — cap runaway tests. Swift Testing exposes only `.minutes(_:)`.

### Dependency injection

If module resolves dependencies through container (e.g. Factory), register stateless test-bundle mocks **once** at bundle load via `<Module>Tests/_setup/TestContainerSetup.swift` (auto-registration). Don't mutate shared container in test bodies. Per-test customization deferred until suite needs it.

## 9. Fixtures and scenes

Two layers, hybrid by design:

- **Atomic fixtures** — `Type.fixture(...)` extensions, one file per model type in `_setup/Fixtures/`. Each `fixture` takes interesting init params with sensible defaults, inserts into supplied context (for persisted types), returns inserted instance, `@discardableResult`.
- **Composite scenes** — builders in `_setup/Scenes/` for multi-level trees (3+ levels of inserts).

Prefer atomic fixtures for single entities; use scene only when test needs populated tree.

## 10. Environment (modules with a backing store)

If module backed by store (e.g. SwiftData), provide per-test in-memory environment building fresh container per test so suites stay hermetic under parallel execution. `DomainTestEnvironment` = reference: `makeInMemory()` reuses cached immutable `Schema`, builds fresh in-memory `ModelContainer` (`isStoredInMemoryOnly: true`) from module's `CurrentSchema` + `MigrationPlan`. Modules with no persistence need no environment — construct inputs directly.

## 11. Verification helpers

Verification helpers must be placed in separate files under `_setup/Verifications/` only when used by **more than one** file (assertion helpers and query glue both qualify). 
_Exception:_ shared verification helpers can be placed into TestEnvironment extension if they need env properties and it shortens their call signature.
Single-file helpers stay `private` in their test file. Assertion helpers forward `sourceLocation` so failures point at call site:

```swift
func metric(
    _ metric: Metric,
    in progression: Progression,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> MetricComparison {
    try #require(progression.metrics.first { $0.metric == metric }, sourceLocation: sourceLocation)
}
```

Query glue follows same rule — e.g. generic `fetchIds(matching:)` returning `Set` of identities, shared by every predicate suite so call sites never depend on fetch order.

## 12. Known issues

Wrap temporarily-failing expectation in `withKnownIssue` (don't disable test) so suite stays green while issue tracked, and test fails loudly if bug fixed:

```swift
withKnownIssue("flaky until #123 lands") {
    #expect(somethingNotYetFixed())
}
```

## 13. Tag taxonomy

Two layers:

- **Shared baseline** (every module): `.edgeCase` (boundary inputs, clamps, empty/nil paths) and `.slow` (slower than ~100 ms; opt-in via filter).
- **Module area tags** — each module seeds own in `<Module>Tests/_setup/Tags.swift` for source areas. Domain's set: `.ops`, `.predicate`, `.stats`, `.schema`, `.extensions`, `.superset`. New modules define own area tags.

Apply at least one area tag on every suite.

## 14. SwiftData specifics (when applicable)

- `ModelContext` is `@MainActor` → SwiftData-backed suites are `@MainActor`, pinning `@Test`s to main actor. Swift Testing still parallelizes **across** suites (separate environments), never **within** `@MainActor` suite against same context.
- One `ModelContainer` per test, in-memory — never share container between tests.
- Cache immutable `Schema` once, reuse across containers; keep container fresh per test.
- Build trees with explicit `position` values (start at 10, step 10) so ordered accessors are deterministic.
- Set relationships both ways where production code expects it (e.g. `set.group = group`).
- Never assert on unsorted fetch order — compare as `Set` or via keyed lookup, or sort explicitly.

## 15. CI

`RunAllTests` against module's test plan must be green with parallelism **on** (default). Red run caused by parallelism = setup bug, not reason to serialize — fix setup. `iOS` scheme's plan also exercises each module's unit tests, so app CI covers them too.

## 16. Anti-patterns

- ❌ Mutating shared DI container in test body.
- ❌ Sharing `ModelContainer` or context across tests.
- ❌ Force-unwraps (`!`) or `try!` / `as!` in test bodies.
- ❌ `#expect(!flag)` — use `== false`.
- ❌ `#expect(throws: Error.self)` — name specific error.
- ❌ Asserting on unsorted fetch order.
- ❌ Disabling parallelism to "fix" flake.
- ❌ Adding infrastructure in feature test PR — compose existing fixtures/scenes/verifications instead.

## 17. Documentation discipline for `_setup/`

Every file under `_setup/` carries:

- Standard file-header comment block (per `styleguide.md`).
- Top-of-symbol `///` doc on primary type describing purpose.
- `/// Example:` fenced snippet showing one typical call site.
- `///` on every public type, function, computed property.
- Short inline `// Why:` where design choice is subtle.