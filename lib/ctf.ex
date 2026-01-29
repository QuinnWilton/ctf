defmodule CTF do
  @moduledoc """
  Encode and decode BEAM compact term format.

  The compact term format is used in the Code chunk of BEAM files to
  efficiently encode instruction arguments. This module provides functions
  to decode these bytes into Elixir terms and encode terms back to bytes.

  ## Supported Features

  - **Tags 0-6**: Literal, Integer, Atom, X-reg, Y-reg, Label, Character
  - **Small values** (0-15): Single-byte encoding
  - **Medium values** (16-2047): Two-byte encoding
  - **Large values** (2048+): Multi-byte encoding
  - **Negative integers**: Two's complement encoding with sign extension
  - **Extended tag 7**: Extended formats (see below)

  ## Extended Formats

  Extended formats (tag 7) provide additional encoding capabilities:

  - **Float literals**: `{:float, F}` - 8-byte IEEE 754 double (tag `0x07`)
  - **Lists**: `{:list, [...]}` - instruction argument lists (tag `0x17`)
  - **Float registers**: `{:fr, N}` - float arithmetic registers (tag `0x27`)
  - **Allocation lists**: `{:alloc, [...]}` - allocation info (tag `0x37`)
  - **Extended literals**: `{:literal, N}` - large literal indices (tag `0x47`)
  - **Typed registers**: `{:tr, reg, type}` - type-annotated registers (tag `0x57`)

  ## Format Reference

  Each encoded argument starts with a tag byte:

      Bits: VVVV_0TTT  (small value, 1 byte total)
            VVVVV_1TTT (medium value, 2 bytes total)

  Tags:
  - 0: Literal table index
  - 1: Integer
  - 2: Atom table index
  - 3: X register
  - 4: Y register
  - 5: Label (jump target)
  - 6: Character (unicode codepoint)
  - 7: Extended format

  ## Examples

      iex> CTF.decode(<<0x03>>)
      {{:x, 0}, <<>>}

      iex> CTF.encode({:x, 5})
      <<0x53>>

      iex> CTF.decode_all(<<0x03, 0x04, 0x05>>)
      [{:x, 0}, {:y, 0}, {:f, 0}]

  ## References

  - The BEAM Book: https://blog.stenmans.org/theBeamBook/
  - OTP source: `erts/emulator/beam/beam_load.c`
  - OTP source: `lib/compiler/src/beam_asm.erl`
  """

  import Bitwise

  @tag_literal 0
  @tag_integer 1
  @tag_atom 2
  @tag_x_reg 3
  @tag_y_reg 4
  @tag_label 5
  @tag_character 6
  @tag_extended 7

  # Extended sub-tags (found in second nibble when tag=7).
  @ext_float 0x07
  @ext_list 0x17
  @ext_float_reg 0x27
  @ext_alloc_list 0x37
  @ext_literal 0x47
  @ext_typed_reg 0x57

  @typedoc "A decoded compact term."
  @type compact_term ::
          {:x, non_neg_integer()}
          | {:y, non_neg_integer()}
          | {:f, non_neg_integer()}
          | {:atom, non_neg_integer()}
          | {:literal, non_neg_integer()}
          | {:integer, integer()}
          | {:char, non_neg_integer()}
          | {:float, float()}
          | {:fr, non_neg_integer()}
          | {:tr, compact_term(), non_neg_integer()}
          | {:list, [compact_term()]}
          | {:alloc, [{compact_term(), compact_term()}]}
          | {:extended, byte(), non_neg_integer()}

  @type decode_result :: {compact_term(), binary()}
  @type encode_result :: binary()

  # --- Decoding ---

  @doc """
  Decode a single compact term from binary.

  Returns `{decoded_term, remaining_binary}`.

  ## Examples

      iex> CTF.decode(<<0x03, 0xFF>>)
      {{:x, 0}, <<0xFF>>}

      iex> CTF.decode(<<0x53, 0xAB>>)
      {{:x, 5}, <<0xAB>>}

  """
  @spec decode(binary()) :: decode_result()
  def decode(<<byte, rest::binary>>) do
    tag = byte &&& 0x07

    if tag == @tag_extended do
      decode_extended(byte, rest)
    else
      decode_tagged(tag, byte, rest)
    end
  end

  def decode(<<>>) do
    raise ArgumentError, "unexpected end of input"
  end

  # Decode a non-extended tagged value.
  defp decode_tagged(tag, byte, rest) do
    {value, rest2} = decode_value(tag, byte, rest)
    {tag_to_term(tag, value), rest2}
  end

  # Decode the value portion (handles small, medium, and large encodings).
  # Tag is passed through for sign extension of negative integers.
  defp decode_value(_tag, byte, rest) when (byte &&& 0x08) == 0 do
    # Small value: bits 7-4 contain the value (always positive).
    {byte >>> 4, rest}
  end

  defp decode_value(tag, byte, rest) do
    # Larger value: check bits 5-4 for size.
    decode_larger_value(tag, byte, rest)
  end

  defp decode_larger_value(_tag, byte, rest) when (byte &&& 0x18) == 0x08 do
    # Medium value (2 bytes): 3 bits from first byte + 8 bits from second.
    # Medium values are always positive (max 2047).
    <<next, rest2::binary>> = rest
    value = ((byte &&& 0xE0) >>> 5) <<< 8 ||| next
    {value, rest2}
  end

  defp decode_larger_value(tag, byte, rest) do
    # Large value: next bits encode byte count.
    decode_large_value(tag, byte, rest)
  end

  defp decode_large_value(tag, byte, rest) do
    # Bits 7-5 encode (byte_count - 2), unless all 1s which means even more bytes.
    size_bits = (byte &&& 0xE0) >>> 5

    if size_bits < 7 do
      # 2-9 bytes for the value.
      byte_count = size_bits + 2
      <<value_bytes::binary-size(byte_count), rest2::binary>> = rest
      value = decode_integer_bytes(tag, value_bytes, byte_count)
      {value, rest2}
    else
      # Size itself is encoded in following bytes.
      {size_term, rest2} = decode(rest)
      byte_count = extract_value(size_term) + 9
      <<value_bytes::binary-size(byte_count), rest3::binary>> = rest2
      value = decode_integer_bytes(tag, value_bytes, byte_count)
      {value, rest3}
    end
  end

  # Decode bytes as integer, applying sign extension for negative integers.
  defp decode_integer_bytes(tag, value_bytes, byte_count) do
    <<first_byte, _::binary>> = value_bytes
    unsigned = :binary.decode_unsigned(value_bytes, :big)

    # Sign extension: if tag is integer and high bit set, it's negative.
    if tag == @tag_integer and first_byte > 127 do
      unsigned - (1 <<< (byte_count * 8))
    else
      unsigned
    end
  end

  # Convert tag + value to an Elixir term.
  defp tag_to_term(@tag_literal, n), do: {:literal, n}
  defp tag_to_term(@tag_integer, n), do: {:integer, n}
  defp tag_to_term(@tag_atom, n), do: {:atom, n}
  defp tag_to_term(@tag_x_reg, n), do: {:x, n}
  defp tag_to_term(@tag_y_reg, n), do: {:y, n}
  defp tag_to_term(@tag_label, n), do: {:f, n}
  defp tag_to_term(@tag_character, n), do: {:char, n}

  # Decode extended format (tag 7).
  defp decode_extended(byte, rest) do
    case byte do
      @ext_float ->
        # Float literal: 8 bytes of IEEE 754 double.
        <<float::float-64, rest2::binary>> = rest
        {{:float, float}, rest2}

      @ext_list ->
        decode_list(rest)

      @ext_float_reg ->
        {{:integer, n}, rest2} = decode(rest)
        {{:fr, n}, rest2}

      @ext_alloc_list ->
        decode_alloc_list(rest)

      @ext_literal ->
        {index_term, rest2} = decode(rest)
        # Extract the raw index value from the tagged term.
        index = extract_value(index_term)
        {{:literal, index}, rest2}

      @ext_typed_reg ->
        # Typed register: register followed by type index.
        {reg, rest2} = decode(rest)
        {{:integer, type_index}, rest3} = decode(rest2)
        {{:tr, reg, type_index}, rest3}

      _ ->
        # Unknown extended format - try to decode as value.
        # Pass tag 7 (extended) to skip sign extension.
        {value, rest2} = decode_value(@tag_extended, byte, rest)
        {{:extended, byte &&& 0xF8, value}, rest2}
    end
  end

  # Decode a list of terms (used for instruction arguments like call targets).
  defp decode_list(binary) do
    {{:integer, length}, rest} = decode(binary)
    decode_list_elements(rest, length, [])
  end

  defp decode_list_elements(rest, 0, acc) do
    {{:list, Enum.reverse(acc)}, rest}
  end

  defp decode_list_elements(binary, n, acc) do
    {term, rest} = decode(binary)
    decode_list_elements(rest, n - 1, [term | acc])
  end

  # Decode allocation list (for allocate instructions).
  defp decode_alloc_list(binary) do
    {{:integer, length}, rest} = decode(binary)
    decode_alloc_elements(rest, length, [])
  end

  defp decode_alloc_elements(rest, 0, acc) do
    {{:alloc, Enum.reverse(acc)}, rest}
  end

  defp decode_alloc_elements(binary, n, acc) do
    {type, rest1} = decode(binary)
    {value, rest2} = decode(rest1)
    decode_alloc_elements(rest2, n - 1, [{type, value} | acc])
  end

  # --- Encoding ---

  @doc """
  Encode an Elixir term to compact binary format.

  ## Examples

      iex> CTF.encode({:x, 0})
      <<0x03>>

      iex> CTF.encode({:x, 5})
      <<0x53>>

      iex> CTF.encode({:x, 100})
      <<0x0B, 0x64>>

  """
  @spec encode(compact_term()) :: encode_result()
  def encode({:x, n}), do: encode_tagged(@tag_x_reg, n)
  def encode({:y, n}), do: encode_tagged(@tag_y_reg, n)
  def encode({:f, n}), do: encode_tagged(@tag_label, n)
  def encode({:atom, n}), do: encode_tagged(@tag_atom, n)
  def encode({:integer, n}) when n >= 0, do: encode_tagged(@tag_integer, n)
  def encode({:integer, n}) when n < 0, do: encode_negative_integer(n)
  def encode({:literal, n}), do: encode_tagged(@tag_literal, n)
  def encode({:char, n}), do: encode_tagged(@tag_character, n)

  def encode({:float, f}) when is_float(f) do
    <<@ext_float, f::float-64>>
  end

  def encode({:fr, n}) do
    <<@ext_float_reg>> <> encode({:integer, n})
  end

  def encode({:tr, reg, type_index}) do
    <<@ext_typed_reg>> <> encode(reg) <> encode({:integer, type_index})
  end

  def encode({:list, elements}) do
    encoded_elements = Enum.map(elements, &encode/1) |> IO.iodata_to_binary()
    <<@ext_list>> <> encode({:integer, length(elements)}) <> encoded_elements
  end

  def encode({:alloc, pairs}) do
    encoded_pairs =
      pairs
      |> Enum.map(fn {type, value} -> encode(type) <> encode(value) end)
      |> IO.iodata_to_binary()

    <<@ext_alloc_list>> <> encode({:integer, length(pairs)}) <> encoded_pairs
  end

  def encode({:extfunc, mod, func, arity}) do
    # External function reference - encoded as a list.
    encode({:list, [{:atom, mod}, {:atom, func}, {:integer, arity}]})
  end

  def encode(nil), do: encode({:atom, 0})

  # Encode a tagged value.
  defp encode_tagged(tag, value) when value >= 0 and value < 16 do
    # Small value: fits in 4 bits.
    <<value::4, 0::1, tag::3>>
  end

  defp encode_tagged(tag, value) when value >= 0 and value < 2048 do
    # Medium value: 3 high bits in first byte, 8 low bits in second.
    # Format: HHH_0_1_TTT where HHH = (value >> 8) & 0x07, TTT = tag.
    high = value >>> 8 &&& 0x07
    low = value &&& 0xFF
    <<high::3, 0::1, 1::1, tag::3, low::8>>
  end

  defp encode_tagged(tag, value) when value >= 0 do
    # Large value: encode byte count and value.
    value_bytes = encode_unsigned(value)
    byte_count = byte_size(value_bytes)

    if byte_count <= 8 do
      size_bits = byte_count - 2
      <<size_bits::3, 1::1, 1::1, tag::3>> <> value_bytes
    else
      # Very large value: encode size separately.
      size_encoded = encode({:integer, byte_count - 9})
      <<7::3, 1::1, 1::1, tag::3>> <> size_encoded <> value_bytes
    end
  end

  # Encode a negative integer using two's complement.
  defp encode_negative_integer(n) when n >= -0x8000 do
    # Fits in 2 bytes (signed).
    value_bytes = <<n::16-signed>>
    <<0::3, 1::1, 1::1, @tag_integer::3>> <> value_bytes
  end

  defp encode_negative_integer(n) do
    # Larger negative: use minimum bytes with two's complement.
    value_bytes = negative_to_bytes(n)
    byte_count = byte_size(value_bytes)

    if byte_count <= 8 do
      size_bits = byte_count - 2
      <<size_bits::3, 1::1, 1::1, @tag_integer::3>> <> value_bytes
    else
      size_encoded = encode({:integer, byte_count - 9})
      <<7::3, 1::1, 1::1, @tag_integer::3>> <> size_encoded <> value_bytes
    end
  end

  # Convert negative integer to two's complement bytes.
  # Ensures the high bit is set (for sign) and uses minimum bytes.
  defp negative_to_bytes(n) do
    # Figure out how many bytes we need based on the positive magnitude.
    pos_byte_count = byte_size(:binary.encode_unsigned(-n))
    bin = <<n::size(pos_byte_count)-unit(8)-signed>>

    # If high bit is NOT set, we need to prepend 0xFF for sign extension.
    case bin do
      <<0::1, _::bitstring>> -> <<0xFF, bin::binary>>
      <<1::1, _::bitstring>> -> bin
    end
  end

  # Encode an unsigned integer to big-endian bytes.
  # Ensures the high bit is NOT set (so it won't be interpreted as negative).
  defp encode_unsigned(0), do: <<0>>

  defp encode_unsigned(n) when n > 0 do
    bytes = encode_unsigned_loop(n, <<>>)

    # If high bit is set, prepend 0x00 to keep it positive.
    case bytes do
      <<1::1, _::bitstring>> -> <<0x00, bytes::binary>>
      _ -> bytes
    end
  end

  defp encode_unsigned_loop(0, acc), do: acc

  defp encode_unsigned_loop(n, acc) do
    encode_unsigned_loop(n >>> 8, <<n &&& 0xFF, acc::binary>>)
  end

  # --- Value Extraction ---

  # Extract the raw numeric value from a tagged term.
  # Used when decoding extended formats where the index/value
  # is encoded as a regular tagged term.
  defp extract_value({:integer, n}), do: n
  defp extract_value({:literal, n}), do: n
  defp extract_value({:atom, n}), do: n
  defp extract_value({:x, n}), do: n
  defp extract_value({:y, n}), do: n
  defp extract_value({:f, n}), do: n
  defp extract_value({:char, n}), do: n

  # --- Utilities ---

  @doc """
  Decode all terms from a binary until exhausted.

  Returns a list of decoded terms.

  ## Example

      iex> CTF.decode_all(<<0x03, 0x04, 0x05>>)
      [{:x, 0}, {:y, 0}, {:f, 0}]

  """
  @spec decode_all(binary()) :: [compact_term()]
  def decode_all(binary), do: decode_all(binary, [])

  defp decode_all(<<>>, acc), do: Enum.reverse(acc)

  defp decode_all(binary, acc) do
    {term, rest} = decode(binary)
    decode_all(rest, [term | acc])
  end

  @doc """
  Check if encode(decode(binary)) == binary for a single term.

  Useful for testing roundtrip correctness.

  ## Example

      iex> CTF.roundtrip?(<<0x03>>)
      true

  """
  @spec roundtrip?(binary()) :: boolean()
  def roundtrip?(binary) do
    {term, <<>>} = decode(binary)
    encode(term) == binary
  rescue
    _ -> false
  end
end
