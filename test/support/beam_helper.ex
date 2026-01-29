defmodule CTF.Test.BeamHelper do
  @moduledoc """
  Test utilities for loading and analyzing BEAM files.
  """

  @doc """
  Get the Code chunk binary from a module.

  Returns `{:ok, code_binary}` or `{:error, reason}`.
  """
  @spec get_code_chunk(module()) :: {:ok, binary()} | {:error, term()}
  def get_code_chunk(module) when is_atom(module) do
    case :code.get_object_code(module) do
      {^module, binary, _filename} ->
        get_code_chunk_from_binary(binary)

      :error ->
        {:error, {:module_not_found, module}}
    end
  end

  @doc """
  Get the Code chunk from a BEAM binary.
  """
  @spec get_code_chunk_from_binary(binary()) :: {:ok, binary()} | {:error, term()}
  def get_code_chunk_from_binary(binary) when is_binary(binary) do
    case :beam_lib.chunks(binary, [~c"Code"]) do
      {:ok, {_, [{~c"Code", code_binary}]}} ->
        {:ok, code_binary}

      {:error, :beam_lib, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extract the bytecode portion from a Code chunk (skip the 20-byte header).
  """
  @spec extract_bytecode(binary()) :: binary()
  def extract_bytecode(<<_header::binary-size(20), bytecode::binary>>) do
    bytecode
  end

  @doc """
  Compile an Elixir code string and return the bytecode.
  """
  @spec compile_string(String.t()) :: {module(), binary()}
  def compile_string(code) do
    [{module, bytecode}] = Code.compile_string(code)
    :code.load_binary(module, ~c"#{module}.beam", bytecode)
    {module, bytecode}
  end

  @doc """
  Purge a module from the code server.
  """
  @spec purge_module(module()) :: :ok
  def purge_module(module) do
    :code.purge(module)
    :code.delete(module)
    :ok
  end

  @doc """
  Get the path to a module's .beam file.
  """
  @spec beam_path(module()) :: {:ok, String.t()} | {:error, term()}
  def beam_path(module) when is_atom(module) do
    case :code.which(module) do
      :non_existing -> {:error, {:module_not_found, module}}
      :preloaded -> {:error, :preloaded}
      path when is_list(path) -> {:ok, to_string(path)}
    end
  end
end
