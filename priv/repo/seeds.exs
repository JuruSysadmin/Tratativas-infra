alias Chat.Repo
alias Chat.Treatments.Reason

# Run with: mix run priv/repo/seeds.exs
#
# The catalog is keyed by `code`, so this seed can be safely rerun. The
# escalation flag and rules from the original specification are intentionally
# not persisted here because the current schema has no corresponding fields or
# table yet.

now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

reasons = [
  {"ACIDENTE_VEICULO", "Acidente provocado por veículo da Jurunense", "critical"},
  {"RECLAME_AQUI", "Cliente oriundo do Reclame Aqui", "critical"},
  {"ENTREGA_ENDERECO_ERRADO", "Entrega realizada no endereço errado", "critical"},
  {"RECOLHIMENTO_TROCA_ATRASADO", "Recolhimento de item para troca atrasado", "critical"},
  {"PRODUTO_ENTREGUE_ERRADO", "Produto entregue errado", "high"},
  {"SOLICITACAO_RECOLHIMENTO_TROCA", "Solicitação de recolhimento de item para troca", "high"},
  {"ENVIO_CREDITO_EMAIL", "Envio de crédito por e-mail", "high"},
  {"ENTREGA_ATRASADA", "Entrega atrasada", "medium"},
  {"SOLICITACAO_STATUS_ENTREGA", "Solicitação de status da entrega", "medium"},
  {
    "PRAZO_ENTREGA_ITEM_TROCA",
    "Informação sobre prazo para entrega de item recolhido para troca",
    "medium"
  },
  {"REAGENDAR_ENTREGA", "Cliente deseja reagendar a entrega", "medium"},
  {"ANTECIPAR_ENTREGA", "Cliente deseja antecipar a entrega", "medium"},
  {"RETIRAR_PEDIDO_ENTREGA", "Cliente deseja retirar seu pedido de entrega", "medium"},
  {"RETIRAR_ITENS_RP", "Cliente deseja saber se já pode retirar itens de RP", "medium"},
  {
    "INCLUIR_OBS_ENTREGA",
    "Cliente deseja incluir observação no pedido, como instrução de entrega",
    "medium"
  },
  {"DUVIDA_PRODUTO", "Dúvidas gerais sobre produtos", "low"},
  {"DUVIDA_PROCEDIMENTO", "Dúvidas gerais sobre procedimentos", "low"},
  {"INFO_JA_DISPONIVEL", "Solicitação de informações já disponíveis", "low"},
  {
    "ALTERAR_OBS_SEM_IMPACTO",
    "Inclusão ou alteração de observação no pedido sem impacto",
    "low"
  },
  {"SEGUNDA_VIA_DOCS", "Solicitação de segunda via de documentos", "low"},
  {"DUVIDA_PAGAMENTO_CREDITO", "Dúvidas sobre formas de pagamento ou crédito", "low"},
  {
    "DUVIDA_PRAZO_ANTES_VENCIMENTO",
    "Dúvidas sobre prazo de entrega antes do vencimento",
    "low"
  },
  {"DUVIDA_RETIRADA_SEM_PENDENCIA", "Dúvidas gerais sobre retirada", "low"},
  {"ATUALIZACAO_CADASTRAL", "Atualização cadastral", "low"},
  {"SOLICITACAO_ADMINISTRATIVA", "Solicitações administrativas sem impacto na entrega", "low"}
]

rows =
  reasons
  |> Enum.with_index(1)
  |> Enum.map(fn {{code, label, priority}, sort_order} ->
    %{
      code: code,
      label: label,
      priority: priority,
      active: true,
      sort_order: sort_order,
      inserted_at: now,
      updated_at: now
    }
  end)

{count, _} =
  Repo.insert_all(Reason, rows,
    on_conflict: {:replace, [:label, :priority, :active, :sort_order, :updated_at]},
    conflict_target: :code
  )

IO.puts("Treatment reasons seeded: #{count}")
