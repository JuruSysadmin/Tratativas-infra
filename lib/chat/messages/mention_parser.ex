defmodule Chat.Messages.MentionParser do
  @moduledoc """
  Extrai ocorrências de menções individuais do conteúdo de uma mensagem.

  Os offsets são medidos em bytes UTF-8 para que possam ser usados com as
  funções binárias do Elixir sem conversões ambíguas entre cliente e servidor.
  """

  @simple_mention_regex ~r/(?:^|[^\p{L}\p{N}_@])@([\p{L}\p{N}](?:[\p{L}\p{N}._-]*[\p{L}\p{N}])?)(?![\p{L}\p{N}_@-])/u
  @simple_handle_regex ~r/^[\p{L}\p{N}](?:[\p{L}\p{N}._-]*[\p{L}\p{N}])?$/u
  @quoted_mention_regex ~r/(?:^|[^\p{L}\p{N}_@])@"([\p{L}\p{N}](?:[^"\r\n]*[\p{L}\p{N}])?)"/u
  @quoted_handle_regex ~r/^[\p{L}\p{N}](?:[^"\r\n]*[\p{L}\p{N}])?$/u
  @max_mentions 50

  @type occurrence :: %{
          handle: String.t(),
          start_offset: non_neg_integer(),
          length: pos_integer()
        }

  @spec parse(term()) :: [occurrence()]
  def parse(content) when is_binary(content) do
    quoted_occurrences = scan(content, @quoted_mention_regex, 2, 1)

    simple_occurrences =
      content
      |> scan(@simple_mention_regex, 1, 0)
      |> Enum.reject(&overlaps?(&1, quoted_occurrences))

    (quoted_occurrences ++ simple_occurrences)
    |> Enum.sort_by(& &1.start_offset)
    |> Enum.take(@max_mentions)
  end

  def parse(_content), do: []

  @spec format(binary()) :: binary()
  def format(username) when is_binary(username) do
    if Regex.match?(@simple_handle_regex, username) do
      "@" <> username
    else
      ~s(@"#{username}")
    end
  end

  @spec mentionable?(term()) :: boolean()
  def mentionable?(username) when is_binary(username) do
    Regex.match?(@quoted_handle_regex, username)
  end

  def mentionable?(_username), do: false

  @spec normalize(binary()) :: binary()
  def normalize(username) when is_binary(username) do
    username
    |> String.normalize(:nfc)
    |> String.downcase()
  end

  defp scan(content, regex, prefix_length, suffix_length) do
    regex
    |> Regex.scan(content, return: :index, capture: :all_but_first)
    |> Enum.map(fn [{handle_offset, handle_length}] ->
      %{
        handle: binary_part(content, handle_offset, handle_length),
        start_offset: handle_offset - prefix_length,
        length: handle_length + prefix_length + suffix_length
      }
    end)
  end

  defp overlaps?(occurrence, quoted_occurrences) do
    Enum.any?(quoted_occurrences, fn quoted ->
      occurrence.start_offset < quoted.start_offset + quoted.length and
        quoted.start_offset < occurrence.start_offset + occurrence.length
    end)
  end
end
