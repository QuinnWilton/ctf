defmodule CTFTest do
  use ExUnit.Case, async: true

  doctest CTF

  describe "decode/1" do
    test "decodes small x-register (0-15)" do
      # x0: tag=3, value=0, encoded as 0000_0011 = 0x03
      assert {{:x, 0}, <<>>} = CTF.decode(<<0x03>>)

      # x5: tag=3, value=5, encoded as 0101_0011 = 0x53
      assert {{:x, 5}, <<>>} = CTF.decode(<<0x53>>)

      # x15: tag=3, value=15, encoded as 1111_0011 = 0xF3
      assert {{:x, 15}, <<>>} = CTF.decode(<<0xF3>>)
    end

    test "decodes small y-register (0-15)" do
      # y0: tag=4, value=0, encoded as 0000_0100 = 0x04
      assert {{:y, 0}, <<>>} = CTF.decode(<<0x04>>)

      # y7: tag=4, value=7, encoded as 0111_0100 = 0x74
      assert {{:y, 7}, <<>>} = CTF.decode(<<0x74>>)
    end

    test "decodes small label (0-15)" do
      # f0: tag=5, value=0, encoded as 0000_0101 = 0x05
      assert {{:f, 0}, <<>>} = CTF.decode(<<0x05>>)

      # f10: tag=5, value=10, encoded as 1010_0101 = 0xA5
      assert {{:f, 10}, <<>>} = CTF.decode(<<0xA5>>)
    end

    test "decodes small atom index (0-15)" do
      # atom 0: tag=2, value=0
      assert {{:atom, 0}, <<>>} = CTF.decode(<<0x02>>)

      # atom 5: tag=2, value=5
      assert {{:atom, 5}, <<>>} = CTF.decode(<<0x52>>)
    end

    test "decodes small integer (0-15)" do
      # integer 0: tag=1, value=0
      assert {{:integer, 0}, <<>>} = CTF.decode(<<0x01>>)

      # integer 10: tag=1, value=10
      assert {{:integer, 10}, <<>>} = CTF.decode(<<0xA1>>)
    end

    test "decodes small literal index (0-15)" do
      # literal 0: tag=0, value=0
      assert {{:literal, 0}, <<>>} = CTF.decode(<<0x00>>)

      # literal 7: tag=0, value=7
      assert {{:literal, 7}, <<>>} = CTF.decode(<<0x70>>)
    end

    test "decodes small character (0-15)" do
      # char 0: tag=6, value=0
      assert {{:char, 0}, <<>>} = CTF.decode(<<0x06>>)

      # char 9: tag=6, value=9
      assert {{:char, 9}, <<>>} = CTF.decode(<<0x96>>)
    end

    test "decodes medium x-register (16-2047)" do
      # For medium encoding: byte1 = (high3 << 5) | 0x08 | tag
      # x100: value=100=0x64, high3=0, byte1=0x0B, byte2=0x64
      assert {{:x, 100}, <<>>} = CTF.decode(<<0x0B, 0x64>>)

      # x1000: high3 = (1000 >> 8) & 0x07 = 3
      # byte1 = (3 << 5) | 0x08 | 3 = 0x6B, byte2 = 1000 & 0xFF = 0xE8
      assert {{:x, 1000}, <<>>} = CTF.decode(<<0x6B, 0xE8>>)
    end

    test "preserves remaining bytes" do
      assert {{:x, 0}, <<0xFF, 0xAB>>} = CTF.decode(<<0x03, 0xFF, 0xAB>>)
    end

    test "decodes list format" do
      # List of 2 elements: {:atom, 1} and {:integer, 2}
      # 0x17 = list tag
      encoded =
        <<0x17>> <>
          CTF.encode({:integer, 2}) <>
          CTF.encode({:atom, 1}) <>
          CTF.encode({:integer, 2})

      {{:list, elements}, <<>>} = CTF.decode(encoded)
      assert elements == [{:atom, 1}, {:integer, 2}]
    end

    test "decodes float literal" do
      # Float: 0x07 tag followed by 8 bytes of IEEE 754 double.
      encoded = <<0x07, 3.14159::float-64>>
      {{:float, value}, <<>>} = CTF.decode(encoded)
      assert_in_delta value, 3.14159, 0.00001
    end

    test "decodes typed register" do
      # Typed register: 0x57 tag, then register, then type index.
      encoded =
        <<0x57>> <>
          CTF.encode({:x, 5}) <>
          CTF.encode({:integer, 42})

      {{:tr, reg, type_index}, <<>>} = CTF.decode(encoded)
      assert reg == {:x, 5}
      assert type_index == 42
    end

    test "decodes float register" do
      encoded = <<0x27>> <> CTF.encode({:integer, 3})
      {{:fr, 3}, <<>>} = CTF.decode(encoded)
    end

    test "decodes allocation list" do
      encoded =
        <<0x37>> <>
          CTF.encode({:integer, 2}) <>
          CTF.encode({:integer, 0}) <>
          CTF.encode({:integer, 5}) <>
          CTF.encode({:integer, 1}) <>
          CTF.encode({:integer, 10})

      {{:alloc, pairs}, <<>>} = CTF.decode(encoded)
      assert pairs == [{{:integer, 0}, {:integer, 5}}, {{:integer, 1}, {:integer, 10}}]
    end

    test "raises on empty input" do
      assert_raise ArgumentError, "unexpected end of input", fn ->
        CTF.decode(<<>>)
      end
    end
  end

  describe "encode/1" do
    test "encodes small x-register (0-15)" do
      assert CTF.encode({:x, 0}) == <<0x03>>
      assert CTF.encode({:x, 5}) == <<0x53>>
      assert CTF.encode({:x, 15}) == <<0xF3>>
    end

    test "encodes small y-register (0-15)" do
      assert CTF.encode({:y, 0}) == <<0x04>>
      assert CTF.encode({:y, 7}) == <<0x74>>
    end

    test "encodes small label (0-15)" do
      assert CTF.encode({:f, 0}) == <<0x05>>
      assert CTF.encode({:f, 10}) == <<0xA5>>
    end

    test "encodes medium values (16-2047)" do
      # x100
      encoded = CTF.encode({:x, 100})
      assert {{:x, 100}, <<>>} = CTF.decode(encoded)

      # x1000
      encoded = CTF.encode({:x, 1000})
      assert {{:x, 1000}, <<>>} = CTF.decode(encoded)

      # x2047 (max medium)
      encoded = CTF.encode({:x, 2047})
      assert {{:x, 2047}, <<>>} = CTF.decode(encoded)
    end

    test "encodes large values (2048+)" do
      # x3000
      encoded = CTF.encode({:x, 3000})
      assert {{:x, 3000}, <<>>} = CTF.decode(encoded)

      # x65535
      encoded = CTF.encode({:x, 65535})
      assert {{:x, 65535}, <<>>} = CTF.decode(encoded)
    end

    test "encodes list" do
      list = {:list, [{:atom, 1}, {:atom, 2}, {:integer, 42}]}
      encoded = CTF.encode(list)
      {decoded, <<>>} = CTF.decode(encoded)
      assert decoded == list
    end

    test "encodes negative integers" do
      for n <- [-1, -15, -16, -127, -128, -2047, -2048, -32768, -65536] do
        encoded = CTF.encode({:integer, n})
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == {:integer, n}, "failed for #{n}"
      end
    end

    test "encodes float literal" do
      encoded = CTF.encode({:float, 3.14159})
      {{:float, value}, <<>>} = CTF.decode(encoded)
      assert_in_delta value, 3.14159, 0.00001
    end

    test "encodes typed register" do
      term = {:tr, {:x, 5}, 42}
      encoded = CTF.encode(term)
      {decoded, <<>>} = CTF.decode(encoded)
      assert decoded == term
    end

    test "encodes nil as atom 0" do
      assert CTF.encode(nil) == CTF.encode({:atom, 0})
    end

    test "encodes external function reference" do
      term = {:extfunc, 1, 2, 3}
      encoded = CTF.encode(term)
      {decoded, <<>>} = CTF.decode(encoded)
      assert decoded == {:list, [{:atom, 1}, {:atom, 2}, {:integer, 3}]}
    end
  end

  describe "decode_all/1" do
    test "decodes multiple consecutive terms" do
      encoded =
        CTF.encode({:x, 0}) <>
          CTF.encode({:y, 1}) <>
          CTF.encode({:f, 5})

      terms = CTF.decode_all(encoded)
      assert terms == [{:x, 0}, {:y, 1}, {:f, 5}]
    end

    test "returns empty list for empty binary" do
      assert CTF.decode_all(<<>>) == []
    end
  end

  describe "roundtrip?/1" do
    test "returns true for valid encoded term" do
      assert CTF.roundtrip?(<<0x03>>)
      assert CTF.roundtrip?(<<0x53>>)
    end

    test "returns false for invalid binary" do
      refute CTF.roundtrip?(<<0x03, 0xFF>>)
    end
  end

  describe "boundary values" do
    test "large positive integers encode correctly" do
      for value <- [127, 128, 255, 256, 32767, 32768, 65535, 65536] do
        term = {:integer, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term, "Failed for value #{value}"
      end
    end

    test "negative integer boundaries" do
      for value <- [-1, -127, -128, -129, -255, -256, -32767, -32768, -32769] do
        term = {:integer, value}
        encoded = CTF.encode(term)
        {decoded, <<>>} = CTF.decode(encoded)
        assert decoded == term, "Failed for value #{value}"
      end
    end
  end
end
