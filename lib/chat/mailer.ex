defmodule Chat.Mailer do
  @moduledoc "Email delivery interface for the Chat application."

  use Swoosh.Mailer, otp_app: :chat
end
