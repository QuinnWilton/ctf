defmodule CTFPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "roundtrip properties" do
    property "small register values roundtrip correctly" do
      check all(
              reg_type <- member_of([:x, :y]),
              value <- integer(0..15)
            ) do
        term = {reg_type, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "medium register values roundtrip correctly" do
      check all(
              reg_type <- member_of([:x, :y]),
              value <- integer(16..2047)
            ) do
        term = {reg_type, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "large register values roundtrip correctly" do
      check all(
              reg_type <- member_of([:x, :y]),
              value <- integer(2048..100_000)
            ) do
        term = {reg_type, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "labels roundtrip correctly" do
      check all(value <- integer(0..10_000)) do
        term = {:f, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "atom indices roundtrip correctly" do
      check all(value <- integer(0..10_000)) do
        term = {:atom, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "literal indices roundtrip correctly" do
      check all(value <- integer(0..10_000)) do
        term = {:literal, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "character values roundtrip correctly" do
      check all(value <- integer(0..0x10FFFF)) do
        term = {:char, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "non-negative integers roundtrip correctly" do
      check all(value <- integer(0..100_000)) do
        term = {:integer, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "negative integers roundtrip correctly" do
      check all(value <- integer(-100_000..-1)) do
        term = {:integer, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "all integers roundtrip correctly" do
      check all(value <- integer(-1_000_000..1_000_000)) do
        term = {:integer, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "very large integers roundtrip correctly" do
      check all(value <- integer(-10_000_000_000..10_000_000_000)) do
        term = {:integer, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "floats roundtrip correctly" do
      check all(value <- float()) do
        term = {:float, value}
        encoded = CTF.encode(term)
        {{:float, decoded_value}, <<>>} = CTF.decode(encoded)
        # Handle NaN specially since NaN != NaN.
        if :erlang.is_number(value) and value != value do
          assert decoded_value != decoded_value
        else
          assert decoded_value == value
        end
      end
    end

    property "float registers roundtrip correctly" do
      check all(value <- integer(0..100)) do
        term = {:fr, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "typed registers roundtrip correctly" do
      check all(
              reg_type <- member_of([:x, :y]),
              reg_num <- integer(0..1000),
              type_index <- integer(0..100)
            ) do
        term = {:tr, {reg_type, reg_num}, type_index}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "simple lists roundtrip correctly" do
      check all(
              length <- integer(0..10),
              elements <- list_of(integer(0..100), length: length)
            ) do
        term = {:list, Enum.map(elements, &{:integer, &1})}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end

    property "allocation lists roundtrip correctly" do
      check all(
              length <- integer(0..5),
              pairs <-
                list_of(
                  {integer(0..10), integer(0..100)},
                  length: length
                )
            ) do
        term = {:alloc, Enum.map(pairs, fn {t, v} -> {{:integer, t}, {:integer, v}} end)}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term
      end
    end
  end

  describe "encoding size properties" do
    property "small values encode to 1 byte" do
      check all(
              tag <- member_of([:x, :y, :f, :atom, :literal, :integer, :char]),
              value <- integer(0..15)
            ) do
        term = {tag, value}
        encoded = CTF.encode(term)
        assert byte_size(encoded) == 1
      end
    end

    property "medium values encode to 2 bytes" do
      check all(
              tag <- member_of([:x, :y, :f, :atom, :literal, :integer, :char]),
              value <- integer(16..2047)
            ) do
        term = {tag, value}
        encoded = CTF.encode(term)
        assert byte_size(encoded) == 2
      end
    end
  end

  describe "decode_all properties" do
    property "decode_all decodes all encoded terms" do
      check all(
              count <- integer(1..10),
              values <- list_of(integer(0..100), length: count)
            ) do
        terms = Enum.map(values, &{:integer, &1})
        encoded = Enum.map(terms, &CTF.encode/1) |> IO.iodata_to_binary()
        decoded = CTF.decode_all(encoded)
        assert decoded == terms
      end
    end
  end
end
