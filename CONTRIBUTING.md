# Contributing to ExpysSDK (Swift)

## Dev setup

The package is self-contained (Foundation only, zero runtime dependencies) and
lives in the Expys monorepo at `packages/sdk-swift`. Work from that directory.
You need the Swift 6 toolchain (Xcode 16+ on Apple platforms, or a `swift:6.x`
toolchain on Linux).

```sh
cd packages/sdk-swift
swift build
```

Local tooling (install once):

```sh
brew install swiftlint   # swift-format ships with the Swift toolchain
```

## Commands

Run from `packages/sdk-swift`:

```sh
swift build -Xswiftc -strict-concurrency=complete   # build (Swift 6, complete checking)
swift test                                           # run the Swift Testing suite
swift test --enable-code-coverage                    # run with coverage
swift Scripts/check-coverage.swift "$(swift test --enable-code-coverage --show-codecov-path)" 90

# Lint + format (CI runs both with warnings-as-errors):
swiftlint --strict
find Sources Tests Examples -name '*.swift' -not -path '*/Generated/*' -print0 \
  | xargs -0 swift format lint --strict
swift format -i -r Sources Tests Examples   # auto-format (never touch Generated/)

# Documentation (the Swift-DocC plugin is gated behind EXPYS_BUILD_DOCS so
# consumers keep a zero-dependency graph):
EXPYS_BUILD_DOCS=1 swift package --disable-sandbox generate-documentation --target ExpysSDK

# Apple-platform build/test (a macOS host with simulators):
xcodebuild -scheme ExpysSDK -destination 'platform=iOS Simulator,name=iPhone 16' test

# CocoaPods packaging validation:
pod lib lint ExpysSDK.podspec
```

### Integration suite (opt-in, real sandbox)

`SandboxIntegrationTests` is skipped unless both env vars are set; it never runs
in normal CI:

```sh
EXPYS_INTEGRATION=1 EXPYS_MEMBER_TOKEN=<sandbox member token> \
  swift test --filter SandboxIntegrationTests
```

## House rules

- No emojis in code, comments, or docs.
- Immutability; functional style where idiomatic.
- TDD: write tests first; keep coverage at or above the 90% gate.
- Small, cohesive files. Keep the public surface intentional and `Sendable`.
- Every new public symbol needs a `///` doc comment (the `swift format`
  `AllPublicDeclarationsHaveDocumentation` rule enforces this).

## Public surface and cross-SDK parity

- The method names, configuration option names, error taxonomy, retry/idempotency
  semantics, and `User-Agent` format are a frozen contract shared with the
  TypeScript and Kotlin SDKs. Do not change them here without mirroring the change
  in the other two SDKs and the spec. CI enforces spec drift and native-model
  parity (`native-model-drift`).
- Never hand-edit `Sources/ExpysSDK/Generated/**`; it is produced from
  `packages/api-spec/v1.sdk.json` by OpenAPI Generator. Regenerate via the
  monorepo's `bun run sdk:generate-models`.
- No new runtime dependencies (the SDK is Foundation-only) without sign-off. The
  Swift-DocC plugin is an accepted build-only, env-gated dependency.

## Releasing

Releases are tag-driven (lead engineer, with approval):

```sh
git tag swift/vX.Y.Z
git push origin swift/vX.Y.Z
```

The tag triggers [`sdk-release.yml`](../../.github/workflows/sdk-release.yml): it
re-verifies spec/parity, builds and tests, syncs the embedded `ExpysVersion.sdk`
constant in `Sources/ExpysSDK/Version.swift` from the tag, and mirrors the package
to the public `expys-swift` repo tagged `X.Y.Z` (SwiftPM resolves the plain semver
tag). Never tag or push the mirror without approval.
