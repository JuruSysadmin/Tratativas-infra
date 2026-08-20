defmodule ChatWeb.Time do
  @moduledoc "Formatting helpers for the application's display timezone."

  @brasilia_timezone "America/Sao_Paulo"

  def format(%DateTime{} = datetime, pattern) do
    datetime
    |> DateTime.shift_zone!(@brasilia_timezone)
    |> Calendar.strftime(pattern)
  end

  def format(%NaiveDateTime{} = datetime, pattern) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(@brasilia_timezone)
    |> Calendar.strftime(pattern)
  end
end
