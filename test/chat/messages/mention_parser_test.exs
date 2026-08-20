defmodule Chat.Messages.MentionParserTest do
  use ExUnit.Case, async: true

  alias Chat.Messages.MentionParser

  test "extracts mention occurrences with UTF-8 byte offsets" do
    content = "Olá, @mariana e @joão-silva!"

    assert [
             %{handle: "mariana", start_offset: 6, length: 8},
             %{handle: "joão-silva", start_offset: 17, length: 12}
           ] = MentionParser.parse(content)
  end

  test "extracts a quoted mention whose username contains spaces" do
    content = ~s(Olá @"VANESSA SOUSA DE PAIVA"!)

    assert [
             %{
               handle: "VANESSA SOUSA DE PAIVA",
               start_offset: 5,
               length: 25
             }
           ] = MentionParser.parse(content)
  end

  test "does not extract a simple mention from inside a quoted mention" do
    assert [
             %{handle: "Equipe @alice", start_offset: 0}
           ] = MentionParser.parse(~s(@"Equipe @alice"))
  end

  test "does not treat the domain portion of an email as a mention" do
    assert [] = MentionParser.parse("Envie para suporte@empresa.com")
  end

  test "keeps sentence punctuation outside the handle" do
    assert [%{handle: "mariana", length: 8}] = MentionParser.parse("Olá @mariana.")
  end

  test "rejects handles followed by invalid terminal characters" do
    assert [] = MentionParser.parse("@alice-")
    assert [] = MentionParser.parse("@alice_")
    assert [] = MentionParser.parse("@alice@bob")
  end

  test "keeps repeated occurrences so each position can be rendered" do
    assert [
             %{handle: "ana", start_offset: 0, length: 4},
             %{handle: "ana", start_offset: 9, length: 4}
           ] = MentionParser.parse("@ana e a @ana")
  end

  test "returns an empty list for non-binary input" do
    assert [] = MentionParser.parse(%{})
  end
end
