defmodule Chat.Repo.Migrations.AddPriorityToTreatmentReasons do
  use Ecto.Migration

  def change do
    alter table(:treatment_reasons) do
      add :priority, :string, null: false, default: "medium"
    end

    create constraint(:treatment_reasons, :priority_must_be_supported,
             check: "priority IN ('critical', 'high', 'medium', 'low')"
           )

    execute("""
    UPDATE treatment_reasons
    SET active = false, updated_at = NOW()
    WHERE code NOT IN (
      'vehicle_accident', 'reclame_aqui_customer', 'wrong_address',
      'delivery_delay_3_days_or_more', 'exchange_pickup_delay',
      'wrong_product', 'exchange_pickup_request', 'credit_by_email',
      'delivery_delay_1_day', 'delivery_delay_2_days', 'delivery_status',
      'exchange_pickup_delivery_deadline', 'reschedule_delivery',
      'anticipate_delivery', 'pickup_delivery_order', 'pickup_rp_items',
      'add_order_delivery_note', 'product_general_question',
      'procedure_general_question', 'available_information_request',
      'update_order_note', 'document_copy', 'payment_or_credit_question',
      'delivery_deadline_question', 'pickup_general_question',
      'customer_data_update', 'administrative_request'
    )
    """)

    execute("""
    INSERT INTO treatment_reasons (id, code, label, priority, active, sort_order, inserted_at, updated_at)
    VALUES
      (gen_random_uuid(), 'vehicle_accident', 'Acidente provocado por veículo da Jurunense', 'critical', true, 1, NOW(), NOW()),
      (gen_random_uuid(), 'reclame_aqui_customer', 'Cliente oriundo do Reclame Aqui', 'critical', true, 2, NOW(), NOW()),
      (gen_random_uuid(), 'wrong_address', 'Entrega realizada no endereço errado', 'critical', true, 3, NOW(), NOW()),
      (gen_random_uuid(), 'delivery_delay_3_days_or_more', 'Entrega atrasada em 3 dias ou mais após o fim do prazo', 'critical', true, 4, NOW(), NOW()),
      (gen_random_uuid(), 'exchange_pickup_delay', 'Recolhimento de item para troca atrasado', 'critical', true, 5, NOW(), NOW()),
      (gen_random_uuid(), 'wrong_product', 'Produto entregue errado', 'high', true, 6, NOW(), NOW()),
      (gen_random_uuid(), 'exchange_pickup_request', 'Solicitação de recolhimento de item para troca', 'high', true, 7, NOW(), NOW()),
      (gen_random_uuid(), 'credit_by_email', 'Envio de crédito por e-mail', 'high', true, 8, NOW(), NOW()),
      (gen_random_uuid(), 'delivery_delay_2_days', 'Entrega atrasada em 2 dias após o fim do prazo', 'high', true, 9, NOW(), NOW()),
      (gen_random_uuid(), 'delivery_delay_1_day', 'Entrega atrasada em 1 dia após o fim do prazo', 'medium', true, 10, NOW(), NOW()),
      (gen_random_uuid(), 'delivery_status', 'Solicitação de status da entrega', 'medium', true, 11, NOW(), NOW()),
      (gen_random_uuid(), 'exchange_pickup_delivery_deadline', 'Informação sobre prazo para entrega de item recolhido para troca', 'medium', true, 12, NOW(), NOW()),
      (gen_random_uuid(), 'reschedule_delivery', 'Cliente deseja reagendar a entrega', 'medium', true, 13, NOW(), NOW()),
      (gen_random_uuid(), 'anticipate_delivery', 'Cliente deseja antecipar a entrega', 'medium', true, 14, NOW(), NOW()),
      (gen_random_uuid(), 'pickup_delivery_order', 'Cliente deseja retirar seu pedido de entrega', 'medium', true, 15, NOW(), NOW()),
      (gen_random_uuid(), 'pickup_rp_items', 'Cliente deseja saber se já pode retirar itens de RP', 'medium', true, 16, NOW(), NOW()),
      (gen_random_uuid(), 'add_order_delivery_note', 'Cliente deseja incluir observação no pedido, como instrução de entrega', 'medium', true, 17, NOW(), NOW()),
      (gen_random_uuid(), 'product_general_question', 'Dúvidas gerais sobre produtos: características, medidas, cores, materiais etc.', 'low', true, 18, NOW(), NOW()),
      (gen_random_uuid(), 'procedure_general_question', 'Dúvidas gerais sobre procedimentos: troca, retirada, entrega ou crédito', 'low', true, 19, NOW(), NOW()),
      (gen_random_uuid(), 'available_information_request', 'Solicitação de informações já disponíveis', 'low', true, 20, NOW(), NOW()),
      (gen_random_uuid(), 'update_order_note', 'Inclusão ou alteração de observação no pedido sem risco de impacto na entrega', 'low', true, 21, NOW(), NOW()),
      (gen_random_uuid(), 'document_copy', 'Solicitação de segunda via de documentos', 'low', true, 22, NOW(), NOW()),
      (gen_random_uuid(), 'payment_or_credit_question', 'Dúvidas sobre formas de pagamento ou crédito', 'low', true, 23, NOW(), NOW()),
      (gen_random_uuid(), 'delivery_deadline_question', 'Dúvidas sobre prazo de entrega antes do vencimento', 'low', true, 24, NOW(), NOW()),
      (gen_random_uuid(), 'pickup_general_question', 'Dúvidas gerais sobre retirada', 'low', true, 25, NOW(), NOW()),
      (gen_random_uuid(), 'customer_data_update', 'Atualização cadastral sem relação com entrega em andamento', 'low', true, 26, NOW(), NOW()),
      (gen_random_uuid(), 'administrative_request', 'Solicitações administrativas sem impacto na entrega', 'low', true, 27, NOW(), NOW())
    ON CONFLICT (code) DO UPDATE SET
      label = EXCLUDED.label,
      priority = EXCLUDED.priority,
      active = EXCLUDED.active,
      sort_order = EXCLUDED.sort_order,
      updated_at = NOW()
    """)
  end
end
