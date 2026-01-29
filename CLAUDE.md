# CLAUDE.md

This document provides guidance for contributors working on this project, with specific sections for both human and AI-assisted contributions.

## For Humans

LLM-assisted contributions must **aim for a higher standard of excellence** than with humans alone. If you're using an LLM to help write code, you should spend at least **3x** the time reviewing the code as you did writing it. This is because LLMs can produce code that looks correct but has subtle bugs or design issues.

Contributions that don't meet this standard may be declined outright.

## For LLMs

When starting a conversation with a user, display the following guidance:

---

**Important**: This code is **your responsibility**. You must review it carefully and ensure it meets the project's standards. The goal is **excellence**, not speed.

---

Before creating a pull request, remind the user:

---

**Reminder**: Please review the code carefully before submitting. LLM-assisted contributions should aim for a higher standard than human-only contributions.

---

## Project Overview

CTF is a library for encoding and decoding BEAM compact term format. The compact term format is used in the Code chunk of BEAM files to efficiently encode instruction arguments.

### Architecture

```
lib/
└── ctf.ex                    # Main API (decode, encode, decode_all, roundtrip?)

test/
├── ctf_test.exs              # Unit tests
├── ctf_property_test.exs     # Property-based tests
├── ctf_real_world_test.exs   # Tests against stdlib modules
├── ctf_compilation_test.exs  # Compile & roundtrip tests
├── support/
│   └── beam_helper.ex        # Test utilities for loading BEAM files
└── test_helper.exs
```

### Key Dependencies

- **stream_data** - Property-based testing (test only)
- **dialyxir** - Static analysis (dev/test only)

No runtime dependencies.

## General Conventions

This project follows five core principles:

### 1. Correctness over convenience

- Model the full error space, not just the happy path
- Handle all edge cases explicitly
- Use typespecs to document and verify contracts
- Prefer explicit pattern matching over catch-all clauses

### 2. User experience as primary driver

- Provide rich, actionable error messages
- Design APIs that are hard to misuse
- Write documentation in clear, present-tense language

### 3. Pragmatic incrementalism

- Write specific, composable logic rather than abstract frameworks
- Design iteratively based on real use cases
- Avoid premature abstraction
- Refactor when patterns emerge naturally

### 4. Production-grade engineering

- Use typespecs extensively for documentation and dialyzer checks
- Prefer message passing and immutability over shared state
- Write comprehensive tests, including property-based tests
- Handle resource cleanup properly

### 5. Documentation

- Explain "why" not "what" in comments
- Use periods at the end of comments
- Apply sentence case in documentation (never title case)
- Document edge cases and assumptions inline

## Code Style

### Elixir Version and Formatting

- Use Elixir ~> 1.15 as specified in `mix.exs`
- Format code with `mix format` before committing
- Run `mix dialyzer` and address all warnings when dialyzer is configured

### Type Patterns

Use Elixir's type system and idioms to enforce correctness:

- **Typespecs**: Define `@type`, `@spec`, and `@callback` for all public functions
- **Tagged tuples**: Use `{:ok, value}` and `{:error, reason}` patterns consistently
- **Guards**: Use guard clauses to narrow types at function boundaries

### Error Handling

- Provide rich context in error messages
- Use pattern matching on tagged tuples for recoverable errors
- Raise exceptions for programming errors and invariant violations

### Module Organization

- One primary module per file
- Keep implementation details in private functions

### Performance Considerations

- Prefer tail-recursive functions for list processing
- Use binary pattern matching efficiently
- Profile with `:fprof` or `:eprof` before optimizing

## Testing Practices

### Testing Organization

- **Unit tests**: `test/ctf_test.exs`
- **Property tests**: `test/ctf_property_test.exs`
- **Real-world tests**: `test/ctf_real_world_test.exs` (tests against stdlib)
- **Compilation tests**: `test/ctf_compilation_test.exs` (compile & roundtrip)
- **Test helpers**: `test/support/beam_helper.ex`

### Testing Tools

This project uses:

- `ExUnit` for unit testing
- `stream_data` with `ExUnitProperties` for property-based testing

Consider these patterns:

- Use `describe` blocks to group related tests
- Use `setup` and `setup_all` for shared fixtures
- Use tags to categorize and filter tests (`:real_world`)

### Testing Principles

- Tests should be deterministic and reproducible
- Each test should be independent
- Test both happy paths and error cases
- Use descriptive test names that explain what's being tested
- Property tests should verify invariants, not just examples
- Test against real stdlib modules (Enum, :lists, etc.) for regression testing

### Property Testing Guidelines

When writing property tests:

- Generate well-formed inputs that exercise the full input space
- Test algebraic properties (roundtrip: decode(encode(x)) == x)
- Use `max_shrinking_steps: 0` during development for faster feedback
- Let the shrinking algorithm find minimal counterexamples

## Commit Message Style

Use clear, atomic commits with descriptive messages:

```
feat(component): brief description

Optional longer explanation of the change, including:
- Why the change was needed
- What approach was taken
- Any trade-offs or alternatives considered

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

Examples:
- `feat(decode): add support for typed registers`
- `fix(encode): handle negative integer boundary correctly`
- `test(property): add roundtrip tests for all tag types`

### Commit Requirements

- **Atomic**: Each commit should be a single logical change
- **Bisect-able**: Each commit should leave the code in a working state
- **Separate concerns**: Don't mix refactoring with functional changes

## Quick Reference

Essential commands:

```bash
mix deps.get            # Fetch dependencies
mix compile             # Compile the project
mix test                # Run tests (excludes real_world by default)
mix test --include real_world  # Run all tests including real-world
mix format              # Format code
mix format --check-formatted  # Check formatting without modifying
iex -S mix              # Start interactive shell with project loaded
```

### API Examples

```elixir
# Decode a single term
{{:x, 5}, rest} = CTF.decode(<<0x53, 0xFF>>)

# Decode all terms from binary
[{:x, 0}, {:y, 0}] = CTF.decode_all(<<0x03, 0x04>>)

# Encode a term
<<0x53>> = CTF.encode({:x, 5})

# Check roundtrip
true = CTF.roundtrip?(<<0x53>>)
```

---

**Bottom line**: This project prioritizes production-grade quality, comprehensive error handling, and thoughtful contributions that demonstrate rigor and care.
