defmodule CTFCompilationTest do
  use ExUnit.Case, async: true

  alias CTF.Test.BeamHelper

  @moduletag :compilation

  describe "negative integer literals" do
    test "handles modules with negative integer literals" do
      code = """
      defmodule CTFCompileTest.Negatives do
        def negative_small, do: -1
        def negative_medium, do: -100
        def negative_large, do: -10000
        def negative_boundary, do: -32768
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.Negatives)
    end
  end

  describe "float literals" do
    test "handles modules with float literals" do
      code = """
      defmodule CTFCompileTest.Floats do
        def pi, do: 3.14159
        def negative_float, do: -2.71828
        def large_float, do: 1.0e100
        def small_float, do: 1.0e-100
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.Floats)
    end
  end

  describe "many local variables" do
    test "handles modules with high register indices" do
      # Generate a function with many local variables.
      vars = for i <- 1..50, do: "v#{i} = #{i}"
      var_names = for i <- 1..50, do: "v#{i}"
      sum = Enum.join(var_names, " + ")

      code = """
      defmodule CTFCompileTest.ManyVars do
        def many_vars do
          #{Enum.join(vars, "\n      ")}
          #{sum}
        end
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.ManyVars)
    end
  end

  describe "complex pattern matching" do
    test "handles modules with many labels" do
      code = """
      defmodule CTFCompileTest.Labels do
        def f1(x) when x > 0, do: :positive
        def f1(x) when x < 0, do: :negative
        def f1(_), do: :zero

        def f2(x) do
          cond do
            x > 100 -> :large
            x > 10 -> :medium
            x > 0 -> :small
            true -> :non_positive
          end
        end

        def f3(list) do
          Enum.map(list, fn
            x when x > 0 -> x * 2
            x -> x
          end)
        end
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.Labels)
    end
  end

  describe "binary pattern matching" do
    test "handles modules with binary patterns" do
      code = """
      defmodule CTFCompileTest.Binary do
        def parse_header(<<magic::32, version::16, length::32, rest::binary>>) do
          {magic, version, length, rest}
        end

        def encode_header(magic, version, length) do
          <<magic::32, version::16, length::32>>
        end
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.Binary)
    end
  end

  describe "try/catch/rescue" do
    test "handles modules with exception handling" do
      code = """
      defmodule CTFCompileTest.Exceptions do
        def safe_divide(a, b) do
          try do
            a / b
          rescue
            ArithmeticError -> :error
          catch
            :exit, _ -> :exit
          end
        end
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.Exceptions)
    end
  end

  describe "receive blocks" do
    test "handles modules with receive and timeout" do
      code = """
      defmodule CTFCompileTest.Receive do
        def wait_for_message(timeout) do
          receive do
            {:ok, value} -> {:received, value}
            :stop -> :stopped
          after
            timeout -> :timeout
          end
        end
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.Receive)
    end
  end

  describe "simple module" do
    test "decodes and re-encodes Code chunk identically" do
      code = """
      defmodule CTFCompileTest.Simple do
        def add(a, b), do: a + b
        def sub(a, b), do: a - b
      end
      """

      {_module, bytecode} = BeamHelper.compile_string(code)
      assert_bytecode_roundtrips(bytecode)
    after
      BeamHelper.purge_module(CTFCompileTest.Simple)
    end
  end

  # --- Helper Functions ---

  defp assert_bytecode_roundtrips(bytecode) do
    {:ok, code_binary} = BeamHelper.get_code_chunk_from_binary(bytecode)
    code = BeamHelper.extract_bytecode(code_binary)
    terms = decode_all_safe(code)

    assert length(terms) > 0, "Expected to decode some terms"

    for term <- terms do
      encoded = CTF.encode(term)
      {decoded, <<>>} = CTF.decode(encoded)

      case {term, decoded} do
        {{:float, f1}, {:float, f2}} ->
          if f1 != f1 do
            assert f2 != f2, "NaN roundtrip failed"
          else
            assert f1 == f2, "Float roundtrip failed: #{f1} != #{f2}"
          end

        _ ->
          assert decoded == term, "Roundtrip failed for term: #{inspect(term)}"
      end
    end
  end

  defp decode_all_safe(binary) do
    decode_all_safe(binary, [])
  end

  defp decode_all_safe(<<>>, acc), do: Enum.reverse(acc)

  defp decode_all_safe(<<byte, rest::binary>>, acc) do
    case try_decode(<<byte, rest::binary>>) do
      {:ok, term, remaining} ->
        decode_all_safe(remaining, [term | acc])

      :skip ->
        decode_all_safe(rest, acc)
    end
  end

  defp try_decode(binary) do
    try do
      {term, rest} = CTF.decode(binary)

      if valid_term?(term) do
        {:ok, term, rest}
      else
        :skip
      end
    rescue
      _ -> :skip
    end
  end

  defp valid_term?({:x, n}) when is_integer(n) and n >= 0 and n < 1024, do: true
  defp valid_term?({:y, n}) when is_integer(n) and n >= 0 and n < 1024, do: true
  defp valid_term?({:f, n}) when is_integer(n) and n >= 0, do: true
  defp valid_term?({:atom, n}) when is_integer(n) and n >= 0, do: true
  defp valid_term?({:literal, n}) when is_integer(n) and n >= 0, do: true
  defp valid_term?({:integer, n}) when is_integer(n), do: true
  defp valid_term?({:char, n}) when is_integer(n) and n >= 0, do: true
  defp valid_term?({:float, f}) when is_float(f), do: true
  defp valid_term?({:fr, n}) when is_integer(n) and n >= 0, do: true
  defp valid_term?({:tr, reg, type}) when is_tuple(reg) and is_integer(type), do: true
  defp valid_term?({:list, items}) when is_list(items), do: Enum.all?(items, &valid_term?/1)
  defp valid_term?({:alloc, items}) when is_list(items), do: true
  defp valid_term?(_), do: false
end
