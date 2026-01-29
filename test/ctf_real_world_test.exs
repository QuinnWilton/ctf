defmodule CTFRealWorldTest do
  use ExUnit.Case, async: true

  alias CTF.Test.BeamHelper

  @moduletag :real_world

  # Elixir stdlib modules with various bytecode patterns.
  @elixir_modules [Enum, Map, Keyword, List, String, GenServer, Agent, Task, Stream]

  # Erlang stdlib modules.
  @erlang_modules [:lists, :maps, :ets, :gen_server, :gen_statem, :supervisor, :io, :file]

  # Modules with specific features.
  @binary_modules [:binary, :re]
  @float_modules [:math, Float]
  @large_modules [Kernel, :erlang]

  describe "Elixir stdlib modules" do
    for module <- @elixir_modules do
      @tag target: module
      test "#{inspect(module)} terms roundtrip correctly" do
        assert_module_roundtrips(unquote(module))
      end
    end
  end

  describe "Erlang stdlib modules" do
    for module <- @erlang_modules do
      @tag target: module
      test "#{inspect(module)} terms roundtrip correctly" do
        assert_module_roundtrips(unquote(module))
      end
    end
  end

  describe "binary-heavy modules" do
    for module <- @binary_modules do
      @tag target: module
      test "#{inspect(module)} terms roundtrip correctly" do
        assert_module_roundtrips(unquote(module))
      end
    end
  end

  describe "float-heavy modules" do
    for module <- @float_modules do
      @tag target: module
      test "#{inspect(module)} terms roundtrip correctly" do
        assert_module_roundtrips(unquote(module))
      end
    end
  end

  describe "large modules" do
    for module <- @large_modules do
      @tag target: module
      test "#{inspect(module)} terms roundtrip correctly" do
        assert_module_roundtrips(unquote(module))
      end
    end
  end

  describe "tag coverage" do
    test "all standard modules cover the major tag types" do
      all_modules =
        @elixir_modules ++ @erlang_modules ++ @binary_modules ++ @float_modules ++ @large_modules

      tag_counts =
        Enum.reduce(all_modules, %{}, fn module, acc ->
          case BeamHelper.get_code_chunk(module) do
            {:ok, code_binary} ->
              bytecode = BeamHelper.extract_bytecode(code_binary)
              terms = decode_all_safe(bytecode)
              count_tags(terms, acc)

            {:error, _} ->
              acc
          end
        end)

      # Verify we've seen the core tag types across all modules.
      assert Map.get(tag_counts, :x, 0) > 0, "Expected to find x-registers"
      assert Map.get(tag_counts, :y, 0) > 0, "Expected to find y-registers"
      assert Map.get(tag_counts, :f, 0) > 0, "Expected to find labels"
      assert Map.get(tag_counts, :atom, 0) > 0, "Expected to find atoms"
      assert Map.get(tag_counts, :integer, 0) > 0, "Expected to find integers"
      assert Map.get(tag_counts, :literal, 0) > 0, "Expected to find literals"
    end
  end

  # --- Helper Functions ---

  defp assert_module_roundtrips(module) do
    case BeamHelper.get_code_chunk(module) do
      {:ok, code_binary} ->
        bytecode = BeamHelper.extract_bytecode(code_binary)
        terms = decode_all_safe(bytecode)

        assert length(terms) > 0, "Expected to decode some terms from #{inspect(module)}"

        for term <- terms do
          encoded = CTF.encode(term)
          {decoded, <<>>} = CTF.decode(encoded)

          case {term, decoded} do
            {{:float, f1}, {:float, f2}} ->
              # Handle NaN specially.
              if f1 != f1 do
                assert f2 != f2, "NaN roundtrip failed"
              else
                assert f1 == f2, "Float roundtrip failed: #{f1} != #{f2}"
              end

            _ ->
              assert decoded == term, "Roundtrip failed for term: #{inspect(term)}"
          end
        end

      {:error, reason} ->
        flunk("Failed to load #{inspect(module)}: #{inspect(reason)}")
    end
  end

  # Decode terms from bytecode, skipping opcode bytes.
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

  defp count_tags(terms, acc) do
    Enum.reduce(terms, acc, fn term, inner_acc ->
      tag = elem(term, 0)
      Map.update(inner_acc, tag, 1, &(&1 + 1))
    end)
  end
end
