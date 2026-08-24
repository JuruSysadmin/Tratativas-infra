import { useState } from "react";
import {
  Accordion,
  AccordionItem,
  Button,
  ComposedModal,
  InlineLoading,
  InlineNotification,
  ModalBody,
  ModalFooter,
  ModalHeader,
  preview__IconIndicator as IconIndicator,
  Select,
  SelectItem,
} from "@carbon/react";
import type { Treatment, TreatmentAuditEntry, User } from "../types";
import { MOCK_AGENTS } from "../hooks/useMockSocket";

interface Props {
  treatment: Treatment | null;
  currentUser: User;
  auditLog: TreatmentAuditEntry[];
  onAssignToMe: () => void;
  onResolve: () => void;
  onReopen: () => void;
  onTransfer: (targetId: string) => void;
  pending: boolean;
}

const STATUS: Record<string, { kind: "normal" | "in-progress" | "succeeded" | "not-started"; label: string }> = {
  open: { kind: "normal", label: "Aberto" },
  in_progress: { kind: "in-progress", label: "Em andamento" },
  resolved: { kind: "succeeded", label: "Resolvido" },
  closed: { kind: "not-started", label: "Fechado" },
};

function formatDateTime(iso: string | null): string {
  if (!iso) return "-";
  return new Date(iso).toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatTimeShort(iso: string): string {
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
}

export default function TreatmentPanel({
  treatment,
  currentUser,
  auditLog,
  onAssignToMe,
  onResolve,
  onReopen,
  onTransfer,
  pending,
}: Props) {
  const [showTransfer, setShowTransfer] = useState(false);
  const [selectedAgent, setSelectedAgent] = useState("");

  if (!treatment) {
    return <p className="treatment-empty">Nenhuma tratativa encontrada.</p>;
  }

  const status = STATUS[treatment.status] ?? STATUS.open;
  const isAssignedToMe = treatment.assigned_agent_id === currentUser.id;
  const isLogisticsAgent = currentUser.role === "logistics_agent";
  const isCommercial = currentUser.role === "commercial";
  const canAssign = isLogisticsAgent && (treatment.status === "open" || (treatment.status === "in_progress" && !treatment.assigned_agent_id));
  const canResolve = isLogisticsAgent && treatment.status === "in_progress" && isAssignedToMe;
  const canReopen = (isLogisticsAgent || isCommercial) && treatment.status === "resolved";
  const canTransfer = isLogisticsAgent && treatment.status === "in_progress" && isAssignedToMe;
  const canUnassign = isLogisticsAgent && treatment.status === "in_progress" && isAssignedToMe;
  const hasActions = canAssign || canResolve || canReopen || canTransfer;

  function handleTransfer() {
    if (!selectedAgent) return;
    onTransfer(selectedAgent);
    setShowTransfer(false);
    setSelectedAgent("");
  }

  return (
    <div className="treatment-panel">
      <div className="treatment-status">
        <IconIndicator kind={status.kind} label={status.label} size={16} />
        <span className="treatment-id">#{treatment.id.slice(0, 8)}</span>
      </div>

      <dl className="treatment-details">
        <Detail label="Pedido" value={`#${treatment.order_id}`} />
        <Detail
          label="Agente"
          value={
            treatment.assigned_agent_id
              ? treatment.assigned_agent_id === currentUser.id
                ? `${currentUser.username} (você)`
                : treatment.assigned_agent_id
              : "Não atribuído"
          }
        />
        <Detail label="Atribuído em" value={formatDateTime(treatment.assigned_at)} />
        {treatment.resolved_at && <Detail label="Resolvido por" value={treatment.resolved_by_id ?? "-"} />}
        {treatment.resolved_at && <Detail label="Resolvido em" value={formatDateTime(treatment.resolved_at)} />}
      </dl>

      {(hasActions || canUnassign) && (
        <section className="treatment-actions" aria-labelledby="treatment-actions-title">
          <h2 id="treatment-actions-title">Ações disponíveis</h2>
          {pending && <InlineLoading description="Processando..." iconDescription="Processando ação" />}
          {canAssign && <Button kind="primary" onClick={onAssignToMe} disabled={pending}>Assumir tratativa</Button>}
          {canResolve && <Button kind="primary" onClick={onResolve} disabled={pending}>Resolver tratativa</Button>}
          {canReopen && <Button kind="primary" onClick={onReopen} disabled={pending}>Reabrir tratativa</Button>}
          {canTransfer && <Button kind="tertiary" onClick={() => setShowTransfer(true)} disabled={pending}>Transferir tratativa</Button>}
          {canUnassign && (
            <>
              <Button kind="ghost" disabled>Liberar tratativa</Button>
              <InlineNotification kind="info" lowContrast hideCloseButton title="Indisponível" subtitle="O handler treatment:unassign ainda não está exposto no channel." />
            </>
          )}
        </section>
      )}

      <Accordion align="start" isFlush>
        <AccordionItem title={`Histórico (${auditLog.length})`}>
          {auditLog.length === 0 ? (
            <p className="treatment-empty">Sem eventos registrados.</p>
          ) : (
            <ol className="treatment-audit">
              {auditLog.map((entry) => (
                <li key={entry.id}>
                  <p>{entry.detail ?? entry.event}</p>
                  <span>{entry.actor} · {formatTimeShort(entry.timestamp)}</span>
                </li>
              ))}
            </ol>
          )}
        </AccordionItem>
      </Accordion>

      <ComposedModal open={showTransfer} onClose={() => setShowTransfer(false)}>
        <ModalHeader label={`Pedido #${treatment.order_id}`} title="Transferir tratativa" />
        <ModalBody>
          <InlineNotification
            kind="warning"
            lowContrast
            hideCloseButton
            title="Atenção"
            subtitle="O agente de destino deve ter o papel logistics_agent e ser membro desta sala."
          />
          <Select
            id="transfer-agent"
            labelText="Agente de destino"
            value={selectedAgent}
            onChange={(event) => setSelectedAgent(event.target.value)}
          >
            <SelectItem value="" text="Selecione um agente..." />
            {MOCK_AGENTS.filter((agent) => agent.id !== currentUser.id).map((agent) => (
              <SelectItem key={agent.id} value={agent.id} text={agent.username} />
            ))}
          </Select>
        </ModalBody>
        <ModalFooter
          primaryButtonText="Confirmar transferência"
          secondaryButtonText="Cancelar"
          primaryButtonDisabled={!selectedAgent || pending}
          onRequestSubmit={handleTransfer}
          onRequestClose={() => setShowTransfer(false)}
        >
          {null}
        </ModalFooter>
      </ComposedModal>
    </div>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}
