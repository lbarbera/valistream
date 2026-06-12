# Valistream Swift Style Guide

Based on the [Google Swift Style Guide](https://google.github.io/swift/) with project-specific overrides and additions documented below.

**When this guide is silent on a topic, follow the Google Swift Style Guide.**

## 1. Source File Basics

- **Encoding:** UTF-8.
- **Indentation:** 4 spaces. No tabs.
- **Line length:** Aim for ~120 characters. Hard-wrap long lines at natural break points.
- **Semicolons:** Never used.
- **One statement per line.**
- **Trailing whitespace:** Avoid, except for blank lines within indented MARK section gaps (Xcode behavior).

---

## 2. Import Statements

Imports are organized into **three groups**, in this order:

1. **Local packages** 
2. **Native Apple frameworks** (`Foundation`, `SwiftUI`, `SwiftData`, `AVKit`, `Combine`, `os`, etc.)
3. **Third-party packages** 

**Rules:**
- Alphabetical (ABC) sorting within each group.
- **No blank lines** between import groups.
- Import whole modules; avoid importing individual declarations.

```swift
// ✅ Correct
import Domain
import AVKit
import SwiftData
import SwiftUI
import Factory

// ❌ Wrong — not grouped; not sorted within groups
import SwiftUI
import Domain
import Factory
import SwiftData
```

When a file only needs native frameworks, the local-packages group is simply absent:

```swift
import Foundation
import SwiftData
```

---

## 3. File Header Comments

Every file starts with an Xcode-generated header comment block:

```swift
//
//  FileName.swift
//  TargetName
//
//  Created by Author Name on DD/MM/YYYY.
//
```

- Use the target name as the second line
- One blank line after the header, before imports

---

## 4. MARK Sections

### 4.1 Standard MARK Groups

Types use `// MARK: -` comments to organize members into logical sections. The standard groups and their **fixed order** are:

1. `// MARK: - Nested types`
2. `// MARK: - Lets & Vars`
3. `// MARK: - Lifecycle`
4. `// MARK: - Body parts` *(SwiftUI views only)*
5. `// MARK: - Public`
6. `// MARK: - Internal`
7. `// MARK: - Private`

Additional context-specific MARK groups may appear (e.g., `// MARK: - Actions`), but the groups above have fixed names — do not rename them.

### 4.2 Spacing Around MARK Comments

- **Three blank lines** before every non-first `// MARK: -` comment. This creates strong visual separation between sections.
- **One blank line** after a `// MARK: -` comment, before the first declaration in that section.
- The very first `// MARK: -` in a type body has no blank lines before it (it just goes on next line after the opening brace).

```swift
struct MyView: View {
    // MARK: - Lets & Vars

    @State private var value = 0



    // MARK: - Body parts

    var body: some View {
        Text("Hello")
    }



    // MARK: - Actions

    private func onTap() { }
}
```

### 4.3 MARK Before Extensions

When a file-scope extension groups related sub-views or nested types, place a `// MARK: -` comment **before** the extension:

```swift
// MARK: - Row

extension Parser {
    struct Value: Codable { ... }
}
```

---

## 5. Braces and Control Flow

### 5.1 Opening Braces

Opening braces go on the **same line** as the declaration or statement (K&R style for opening braces):

```swift
struct Foo {
    func bar() {
        if condition {
            ...
        }
    }
}
```

### 5.2 `else` and `catch` — Allman-style *(Override vs Google)*

> **This overrides the Google Swift Style Guide.**

`else`, `catch`, and similar continuation keywords go on a **new line**, not on the same line as the closing brace:

```swift
// ✅ Correct (project style)
if condition {
    doSomething()
}
else {
    doOtherThing()
}

do {
    try riskyOperation()
}
catch {
    handleError(error)
}

// ❌ Wrong (Google K&R style — not used in this project)
if condition {
    doSomething()
} else {
    doOtherThing()
}
```

This applies to all `if/else`, `if let/else`, `do/catch`, and `guard/else` (multi-line form).

### 5.3 Single-line Guards

`guard` statements with simple bodies stay on one line:

```swift
guard value == nil else { return }
guard let section = group.safeSection else { return }
```

Multi-line `guard` only when the condition or body is complex:

```swift
guard let equipment: Equipment = try? modelContext.persistentModel(withId: equipmentId) else {
    return
}
```

---

## 6. Whitespace and Blank Lines

- **One blank line** between properties within a section.
- **One blank line** between methods within a section.
- **Three blank lines** before non-first `// MARK: -` sections (see [Section 4.2](#42-spacing-around-mark-comments)).
- **No blank lines** inside method bodies unless grouping logically distinct steps.
- **One blank line** before `return` in multi-statement functions (optional, for readability).
- **No trailing blank lines** at end of file. File ends with a single newline after the last closing brace.
- Operators (`+`, `-`, `=`, `==`, `&&`, `||`) have spaces on both sides.
- Colons in type annotations have no space before and one space after: `let x: Int`.
- Commas have no space before and one space after.

---

## 7. Naming Conventions

Follow Apple's [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) as the foundation.

### 7.1 Types

- **UpperCamelCase** for types
- Protocols: named as nouns when describing a capability (`NavigationDestination`) or with `-able`/`-ible` suffix.

### 7.2 Functions and Properties

- **lowerCamelCase**: `onDelete()`
- Boolean properties/variables: read as assertions — `isHidden`, `isFulfilled`
- Action handlers: prefixed with `on` — `onTap()`

### 7.3 Enum Cases

- **lowerCamelCase**: `case create`, `case edit(PersistentIdentifier)`.

### 7.4 Constants

- No `k` prefix or `SCREAMING_SNAKE_CASE`. Use lowerCamelCase for all constants, including static ones.

### 7.5 File Naming

- **Single-type files:** Named after the type
- **Extensions adding conformance or category:** `Type+Category.swift` — e.g. `Array+SafeSubscript.swift`

---

## 8. Access Control

### 8.1 General Rules

- Prefer `public` and `private`. Use `internal` only when semantically meaningful (it is the default).
- Avoid `fileprivate` — restructure code to use `private` instead.
- Mark properties and methods as `private` unless they need wider visibility.
- Use `public private(set)` or `public internal(set)` for read-only external access with internal mutability.

## 9. Extensions

### 9.1 Organizing with Extensions

- Use extensions to group logically related functionality.
- Nested views are placed in extensions of their parent type.
- One logical grouping per extension.

### 9.2 `private extension` for Private Helpers

Use `private extension` to scope helper views or functions to the file:

```swift
private extension ValueDetails {
    struct Group: Equatable { ... }
}
```

---

## 10. Closures

### 10.1 Trailing Closure Syntax

Use trailing closures for the last (or only) closure parameter:

```swift
ForEach(values) { value in
    Text(value.name)
}

Button("Delete", role: .destructive, action: { onDelete() })
```

### 10.2 Single-line Closures

Short closures stay on one line:

```swift
action: { onDelete(value) }
.onAppear { durationRedrawTrigger.toggle() }
```

### 10.3 Multi-line Closures

Complex closures use multi-line formatting with the body indented:

```swift
.onAppear {
    guard value == nil else { return }
    let modelContext = DataProvider.shared.modelContainer.mainContext
    ...
}
```

### 10.4 Closure Parameters and Key-Path Syntax

- **Prefer key-path syntax** over closures wherever possible:

```swift
// ✅ Preferred
let totals = metrics.map(\.totalDuration)

// ❌ Avoid when key-path works
let totals = metrics.map({ $0.totalDuration })
```

- Name closure parameters explicitly — avoid `$0` in complex closures.

### 10.5 Multi-parameter Call Sites

When a call site doesn't fit preferred line width (many parameters, trailing closures, or nested initializers), place each parameter on its own line, indented +4 from the call. Move closing parenthesis on its own line:

```swift
ChartSelectionPointer(
    date: selectedMetric.date,
    pointMarkValue: selectedMetric.totalDuration,
    color: .exStatsDuration,
    yOverflowResolution: fullscreen ? .fit : nil,
    annotation: {
        SimpleChartAnnotation(
            heading: selectedMetric.date.date_EEE_d_MMM,
            value: selectedMetric.valueString,
            valueNote: "(" + selectedMetric.valueNote + ")"
        )
    }
)
```

Short call sites with 1–2 simple parameters stay on one line if they fit preferred line width:

```swift
OneLineChartHeader(sysIconName: .sysIconStatsDuration, title: "Duration")
```

### 10.6 Multi-closure Call Sites

When a call site has overloads with multiple closures prefer following order:
1. Check if other overloads with less closure-parameters would do same as good.
    1. If one closure remains, prefer trailing closure syntax where the last closure is an action.
2. Prefer trailing closure syntax where the last closure is a ViewBuilder.
3. For trivial closures, prefer named one-liner if it fits into line width. E.g. `action: { navigator.back() }`
4. Prefer extracting actions into functions to showrten the call site.
5. If call site contains only closures, prefer parenthesis-less syntax. E.g.:
```swift 
Button { 
    ... 
} label: { 
    ... 
}` 
```
Note how `label:` goes in the same line as `}` and `{`. This is the rule for parenthesis-less call sites.

---

## 11. Optional Binding and Guard Statements

### 11.1 Shorthand Optional Binding

Use the shorthand `if let` / `guard let` syntax (Swift 5.7+). Do **not** repeat the variable name:

```swift
// ✅ Correct
if let selectedMetric { ... }
guard let metric else { return nil }
if let section = group.safeSection { ... }

// ❌ Wrong — redundant name repetition
if let selectedMetric = selectedMetric { ... }
guard let metric = metric else { return nil }
```

The explicit `= value` form is only used when binding to a **different name** or a **different expression**:

### 11.2 Guard Statements

- Prefer `guard` for early returns, especially in action handlers.
- Keep `guard` on a single line when the condition and else clause fit:

```swift
guard let section = group.safeSection else { return }
guard !exs.isEmpty else { return }
```

- Multi-line `guard` when the condition or body is complex:

```swift
guard let section = group.section, let idx = section.groups?.firstIndex(of: group) else {
    Log.operations.fault("Trying to remove Group without a Section.")
    return
}
```

- With multi-line conditions, keep `else {` on final condition line:

```swift
guard let set = setItem.set, let group = set.group, let section = group.section,
      section.executionStyle == .superset else {
    return
}
```

---

## 12. Switch Statements

### 12.1 Formatting

- `case` statements at the same indentation as `switch`.
- Body of each case indented +4 spaces from `case`.
- Blank line between cases that have multi-line bodies.
- No blank line between single-line cases.

### 12.2 Implicit Returns

Use implicit returns where possible

### 12.3 Pattern Matching

Bind associated values with `let` inside the case pattern:

```swift
case .edit(let id):
    SceneDetailsView(itemId: id)
```

### 12.4 Exhaustive Matching

Prefer exhaustive matching over `default` when the enum has few cases. Use `default` when the enum has many cases and only a few need special handling.

---

## 13. Error Handling

- Use `try?` for non-critical operations where failure is acceptable:

```swift
value = try? modelContext.persistentModel(withId: valueId)
```

- Use `do/catch` with logging for operations where failure should be recorded:

```swift
do {
    let value = try Value.Ops.createNew(from: template)
    ...
}
catch {
    Log.general.error("Failed to create Value from a Template: %@", String(describing: error))
}
```

- `try!` / force-unwrap: strongly discouraged. Only acceptable in unit tests or truly unrecoverable programmer errors (malformed static regex, etc.).

---

## 14. Comments and Documentation

### 14.1 Documentation Comments

- Use `///` (triple-slash) for documentation. Never use `/** */` block comments.
- Every public type should have a brief documentation comment.
- SwiftUI views get a one-line `///` comment above the struct:

### 14.2 Inline Comments

- Use `//` for inline explanations. Never `/* */`.
- Place inline comments on the line above the code they explain, not at the end of the line (unless very short).
- Use comments sparingly — prefer self-documenting code.

## 15. General Swift instructions

- `@Observable` classes must be marked `@MainActor` unless the project has Main Actor default actor isolation.
- All shared data should use `@Observable` classes with `@State` (for ownership) and `@Bindable` / `@Environment` (for passing).
- Strongly prefer not to use `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject`.
- Assume strict Swift concurrency rules are being applied.
- Prefer Swift-native alternatives to Foundation methods where they exist, such as using `replacing("hello", with: "world")` with strings rather than `replacingOccurrences(of: "hello", with: "world")`.
- Prefer modern Foundation API, for example `URL.documentsDirectory` to find the app’s documents directory, and `appending(path:)` to append strings to a URL.
- Never use C-style number formatting such as `Text(String(format: "%.2f", abs(myNumber)))`; always use `Text(abs(change), format: .number.precision(.fractionLength(2)))` instead.
- Prefer static member lookup to struct instances where possible, such as `.circle` rather than `Circle()`, and `.borderedProminent` rather than `BorderedProminentButtonStyle()`.
- Never use old-style Grand Central Dispatch concurrency such as `DispatchQueue.main.async()`. If behavior like this is needed, always use modern Swift concurrency.
- Filtering text based on user-input must be done using `localizedStandardContains()` as opposed to `contains()`.
- Avoid force unwraps and force `try` unless it is unrecoverable.
- Prefer modern `FormatStyle` API instead of legacy `Formatter` subclasses such as `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. For example, to format a date, use `myDate.formatted(date: .abbreviated, time: .shortened)`. To parse a date from a string, use `Date(inputString, strategy: .iso8601)`. For numbers, use `myNumber.formatted(.number)` or custom format styles.
- Add code comments and documentation comments as needed.
