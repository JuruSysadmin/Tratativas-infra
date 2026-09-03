defmodule Chat.Orders.Client do
  @moduledoc "HTTP client for the orders API used by treatment previews."

  @type customer_summary :: %{customer_id: integer(), customer_name: String.t()}

  @spec get(integer(), String.t()) :: {:ok, customer_summary()} | {:error, atom()}
  def get(order_id, authorization_header)
      when is_integer(order_id) and is_binary(authorization_header) do
    with {:ok, base_url, request_options} <- configuration(),
         {:ok, response} <- request(base_url, request_options, order_id, authorization_header),
         {:ok, item} <- first_item(response.body),
         {:ok, customer} <- customer_summary(item) do
      {:ok, customer}
    end
  end

  def get(_order_id, _authorization_header), do: {:error, :invalid_request}

  @doc """
  Resolves customer summaries for many orders concurrently.

  Orders that fail, time out or are not found are absent from the result, so
  callers can degrade to a view without customer data instead of failing the
  whole response on one bad lookup.
  """
  @spec get_many([integer()], String.t(), keyword()) :: %{integer() => customer_summary()}
  def get_many(order_ids, authorization_header, opts \\ [])
      when is_list(order_ids) and is_binary(authorization_header) do
    order_ids
    |> Task.async_stream(
      fn order_id -> {order_id, get(order_id, authorization_header)} end,
      max_concurrency: Keyword.get(opts, :max_concurrency, 15),
      timeout: Keyword.get(opts, :timeout, 5_000),
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {order_id, {:ok, summary}}}, acc -> Map.put(acc, order_id, summary)
      _outcome, acc -> acc
    end)
  end

  defp configuration do
    config = Application.get_env(:chat, :orders_api, [])
    base_url = Keyword.get(config, :base_url, System.get_env("ORDERS_API_URL"))

    if is_binary(base_url) and base_url != "" do
      {:ok, String.trim_trailing(base_url, "/"), Keyword.get(config, :request_options, [])}
    else
      {:error, :not_configured}
    end
  end

  defp request(base_url, request_options, order_id, authorization_header) do
    options =
      request_options
      |> Keyword.put(:params, orderId: order_id)
      |> Keyword.put(:headers, authorization: authorization_header)

    case Req.get(Path.join(base_url, "orders"), options) do
      {:ok, %{status: 200} = response} -> {:ok, response}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: status}} when status >= 400 -> {:error, :unavailable}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp first_item(%{"items" => [item | _]}) when is_map(item), do: {:ok, item}
  defp first_item(_body), do: {:error, :not_found}

  defp customer_summary(%{"customerId" => id, "customerName" => name})
       when is_integer(id) and is_binary(name) and name != "" do
    {:ok, %{customer_id: id, customer_name: name}}
  end

  defp customer_summary(_item), do: {:error, :invalid_response}
end
