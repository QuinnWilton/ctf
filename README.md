# CTF

[![CI](https://github.com/QuinnWilton/ctf/actions/workflows/ci.yml/badge.svg)](https://github.com/QuinnWilton/ctf/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/ctf.svg)](https://hex.pm/packages/ctf)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ctf)

BEAM compact term format encoder/decoder.

The compact term format is used in the Code chunk of BEAM files to efficiently encode instruction arguments. This library provides functions to decode these bytes into Elixir terms and encode terms back to bytes.

## When to use this library

Use CTF when you need to:

- Parse bytecode arguments from BEAM files
- Analyze or transform compiled Erlang/Elixir code
- Build tools that work with BEAM bytecode

## Installation

Add `ctf` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ctf, "~> 0.1.0"}
  ]
end
```

## Usage

### Decoding

Decode a single compact term from binary:

```elixir
# Decode returns {term, remaining_binary}
{{:x, 0}, <<>>} = CTF.decode(<<0x03>>)
{{:x, 5}, rest} = CTF.decode(<<0x53, 0xFF>>)

# Decode all terms from a binary
[{:x, 0}, {:y, 0}, {:f, 0}] = CTF.decode_all(<<0x03, 0x04, 0x05>>)
```

### Encoding

Encode an Elixir term to compact binary format:

```elixir
<<0x03>> = CTF.encode({:x, 0})
<<0x53>> = CTF.encode({:x, 5})
<<0x0B, 0x64>> = CTF.encode({:x, 100})
```

### Supported term types

| Term | Description | Example |
|------|-------------|---------|
| `{:x, N}` | X register | `{:x, 5}` |
| `{:y, N}` | Y register (stack) | `{:y, 0}` |
| `{:f, N}` | Label (jump target) | `{:f, 42}` |
| `{:atom, N}` | Atom table index | `{:atom, 1}` |
| `{:literal, N}` | Literal table index | `{:literal, 3}` |
| `{:integer, N}` | Integer value | `{:integer, -42}` |
| `{:char, N}` | Unicode codepoint | `{:char, 65}` |
| `{:float, F}` | Float literal | `{:float, 3.14}` |
| `{:fr, N}` | Float register | `{:fr, 0}` |
| `{:tr, reg, type}` | Typed register | `{:tr, {:x, 0}, 5}` |
| `{:list, [...]}` | Argument list | `{:list, [{:atom, 1}]}` |
| `{:alloc, [...]}` | Allocation list | `{:alloc, [{{:integer, 0}, {:integer, 5}}]}` |

## References

- [The BEAM Book](https://blog.stenmans.org/theBeamBook/) - Comprehensive guide to BEAM internals
- OTP source: `erts/emulator/beam/beam_load.c` - Bytecode loader
- OTP source: `lib/compiler/src/beam_asm.erl` - Bytecode assembler
