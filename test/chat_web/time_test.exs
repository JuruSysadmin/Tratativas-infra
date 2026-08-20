defmodule ChatWeb.TimeTest do
  use ExUnit.Case, async: true

  alias ChatWeb.Time

  test "formats UTC DateTime in Brasilia time" do
    datetime = ~U[2026-07-25 15:32:00Z]

    assert Time.format(datetime, "%d/%m · %H:%M") == "25/07 · 12:32"
  end

  test "formats the reported UTC timestamp in Brasilia time" do
    datetime = ~U[2026-07-25 12:02:38.563087Z]

    assert Time.format(datetime, "%H:%M:%S") == "09:02:38"
  end

  test "formats UTC NaiveDateTime in Brasilia time" do
    datetime = ~N[2026-07-25 15:32:00]

    assert Time.format(datetime, "%H:%M") == "12:32"
  end
end
