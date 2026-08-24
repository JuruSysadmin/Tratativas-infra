import { useState, useEffect, useCallback, useRef } from "react";
import type {
  ConnectionState,
  Message,
  SystemMessage,
  ChatItem,
  PresenceUser,
  Room,
  Treatment,
  TreatmentAuditEntry,
  ReadReceiptsMap,
  User,
  Toast,
} from "../types";

const CURRENT_USER: User = {
  id: "agent-001",
  username: "joao.silva",
  role: "logistics_agent",
};

const OTHER_USER: User = {
  id: "commercial-001",
  username: "ana.lima",
  role: "commercial",
};

export const MOCK_AGENTS = [
  { id: "agent-002", username: "marcos.ferreira" },
  { id: "agent-003", username: "carla.mendes" },
  { id: "agent-004", username: "rafael.costa" },
];

function makeMsg(
  id: string,
  content: string,
  userId: string,
  username: string,
  roomId: string,
  minutesAgo: number,
  edited?: boolean
): Message {
  const d = new Date(Date.now() - minutesAgo * 60000);
  return {
    id,
    content,
    user: { id: userId, username },
    room_id: roomId,
    inserted_at: d.toISOString(),
    edited_at: edited ? new Date(d.getTime() + 30000).toISOString() : null,
    attachments: [],
  };
}

function makeSysMsg(
  event: SystemMessage["event"],
  text: string,
  roomId: string,
  minutesAgo: number
): SystemMessage {
  return {
    id: "sys-" + Math.random().toString(36).slice(2),
    kind: "system",
    event,
    text,
    room_id: roomId,
    inserted_at: new Date(Date.now() - minutesAgo * 60000).toISOString(),
  };
}

const INITIAL_ROOMS: Room[] = [
  {
    id: "room-001",
    name: "Pedido #4821",
    order_id: 4821,
    unread_count: 2,
    has_more: true,
    treatment: {
      id: "treat-001",
      order_id: 4821,
      room_id: "room-001",
      status: "in_progress",
      assigned_agent_id: "agent-001",
      assigned_at: new Date(Date.now() - 3600000).toISOString(),
      resolved_by_id: null,
      resolved_at: null,
    },
  },
  {
    id: "room-002",
    name: "Pedido #3917",
    order_id: 3917,
    unread_count: 0,
    has_more: false,
    treatment: {
      id: "treat-002",
      order_id: 3917,
      room_id: "room-002",
      status: "open",
      assigned_agent_id: null,
      assigned_at: null,
      resolved_by_id: null,
      resolved_at: null,
    },
  },
  {
    id: "room-003",
    name: "Pedido #5102",
    order_id: 5102,
    unread_count: 0,
    has_more: false,
    treatment: {
      id: "treat-003",
      order_id: 5102,
      room_id: "room-003",
      status: "resolved",
      assigned_agent_id: "agent-001",
      assigned_at: new Date(Date.now() - 7200000).toISOString(),
      resolved_by_id: "agent-001",
      resolved_at: new Date(Date.now() - 1800000).toISOString(),
    },
  },
  {
    id: "room-004",
    name: "Pedido #2288",
    order_id: 2288,
    unread_count: 1,
    has_more: false,
    treatment: {
      id: "treat-004",
      order_id: 2288,
      room_id: "room-004",
      status: "in_progress",
      assigned_agent_id: "agent-002",
      assigned_at: new Date(Date.now() - 5400000).toISOString(),
      resolved_by_id: null,
      resolved_at: null,
    },
  },
];

const INITIAL_ITEMS: Record<string, ChatItem[]> = {
  "room-001": [
    makeSysMsg("room:joined", "joao.silva entrou na sala", "room-001", 65),
    makeMsg("msg-001", "Olá, tenho um problema com meu pedido.", OTHER_USER.id, OTHER_USER.username, "room-001", 62),
    makeMsg("msg-002", "Bom dia! Pode me informar o número do pedido?", CURRENT_USER.id, CURRENT_USER.username, "room-001", 60),
    makeMsg("msg-003", "O pedido é #4821. A entrega estava prevista para ontem mas não chegou.", OTHER_USER.id, OTHER_USER.username, "room-001", 58),
    makeMsg("msg-004", "Entendido. Vou verificar o status da entrega agora.", CURRENT_USER.id, CURRENT_USER.username, "room-001", 55),
    makeSysMsg("treatment:agent_assigned", "joao.silva assumiu a tratativa", "room-001", 54),
    makeMsg("msg-005", "O pedido está com o transportador e deve chegar hoje até as 18h.", CURRENT_USER.id, CURRENT_USER.username, "room-001", 40),
    makeMsg("msg-006", "Ok, aguardo. Obrigada!", OTHER_USER.id, OTHER_USER.username, "room-001", 38),
    makeMsg("msg-007", "Posso te enviar o código de rastreamento também.", CURRENT_USER.id, CURRENT_USER.username, "room-001", 10, true),
  ],
  "room-002": [
    makeMsg("msg-101", "Precisamos alinhar sobre o pedido #3917.", OTHER_USER.id, OTHER_USER.username, "room-002", 120),
    makeMsg("msg-102", "Claro, qual é o problema?", CURRENT_USER.id, CURRENT_USER.username, "room-002", 118),
  ],
  "room-003": [
    makeMsg("msg-201", "O pedido foi entregue com sucesso!", CURRENT_USER.id, CURRENT_USER.username, "room-003", 200),
    makeMsg("msg-202", "Perfeito, muito obrigado pelo suporte.", OTHER_USER.id, OTHER_USER.username, "room-003", 195),
    makeSysMsg("treatment:resolved", "joao.silva resolveu a tratativa", "room-003", 180),
  ],
  "room-004": [
    makeMsg("msg-301", "Há uma divergência nos itens entregues.", OTHER_USER.id, OTHER_USER.username, "room-004", 90),
  ],
};

const OLDER_MESSAGES: Record<string, ChatItem[]> = {
  "room-001": [
    makeMsg("old-001", "Boa tarde, é a primeira vez que entro em contato.", OTHER_USER.id, OTHER_USER.username, "room-001", 180),
    makeMsg("old-002", "Olá! Em que posso ajudar?", CURRENT_USER.id, CURRENT_USER.username, "room-001", 178),
    makeMsg("old-003", "Tenho dúvidas sobre o prazo de entrega.", OTHER_USER.id, OTHER_USER.username, "room-001", 175),
  ],
};

const INITIAL_PRESENCE: Record<string, PresenceUser[]> = {
  "room-001": [
    { id: CURRENT_USER.id, username: CURRENT_USER.username, typing: false, joined_at: new Date(Date.now() - 3600000).toISOString() },
    { id: OTHER_USER.id, username: OTHER_USER.username, typing: false, joined_at: new Date(Date.now() - 3500000).toISOString() },
  ],
  "room-002": [
    { id: CURRENT_USER.id, username: CURRENT_USER.username, typing: false, joined_at: new Date().toISOString() },
  ],
  "room-003": [],
  "room-004": [
    { id: "agent-002", username: "marcos.ferreira", typing: false, joined_at: new Date(Date.now() - 1000000).toISOString() },
  ],
};

const INITIAL_AUDIT: TreatmentAuditEntry[] = [
  {
    id: "audit-001",
    event: "treatment:agent_assigned",
    actor: "joao.silva",
    timestamp: new Date(Date.now() - 3600000).toISOString(),
    detail: "Assumiu a tratativa",
  },
];

export function useMockSocket() {
  const [connectionState, setConnectionState] = useState<ConnectionState>("idle");
  const [rooms, setRooms] = useState<Room[]>(INITIAL_ROOMS);
  const [activeRoomId, setActiveRoomId] = useState<string>("room-001");
  const [items, setItems] = useState<Record<string, ChatItem[]>>(INITIAL_ITEMS);
  const [presence, setPresence] = useState<Record<string, PresenceUser[]>>(INITIAL_PRESENCE);
  const [readReceipts, setReadReceipts] = useState<ReadReceiptsMap>({});
  const [editingMessage, setEditingMessage] = useState<Message | null>(null);
  const [commandPending, setCommandPending] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [loadingMore, setLoadingMore] = useState(false);
  const [auditLog, setAuditLog] = useState<TreatmentAuditEntry[]>(INITIAL_AUDIT);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const currentUser = CURRENT_USER;

  useEffect(() => {
    setConnectionState("connecting");
    const t = setTimeout(() => {
      setConnectionState("connected");
      setRooms((prev) => prev.map((r) => (r.id === "room-001" ? { ...r, unread_count: 0 } : r)));
      // Simulate read_receipts:updated for last message
      setReadReceipts({ "msg-007": [OTHER_USER.id] });
    }, 800);
    return () => clearTimeout(t);
  }, []);

  // Simulate other user typing in room-001
  useEffect(() => {
    if (activeRoomId !== "room-001" || connectionState !== "connected") return;
    const interval = setInterval(() => {
      if (Math.random() < 0.12) {
        setPresence((prev) => ({
          ...prev,
          [activeRoomId]: (prev[activeRoomId] ?? []).map((u) =>
            u.id === OTHER_USER.id ? { ...u, typing: true } : u
          ),
        }));
        setTimeout(() => {
          setPresence((prev) => ({
            ...prev,
            [activeRoomId]: (prev[activeRoomId] ?? []).map((u) =>
              u.id === OTHER_USER.id ? { ...u, typing: false } : u
            ),
          }));
        }, 2800);
      }
    }, 9000);
    return () => clearInterval(interval);
  }, [activeRoomId, connectionState]);

  const addToast = useCallback((type: Toast["type"], title: string, subtitle?: string) => {
    const id = Math.random().toString(36).slice(2);
    setToasts((q) => [...q, { id, type, title, subtitle }]);
    setTimeout(() => setToasts((q) => q.filter((t) => t.id !== id)), 5000);
  }, []);

  const dismissToast = useCallback((id: string) => {
    setToasts((q) => q.filter((t) => t.id !== id));
  }, []);

  const selectRoom = useCallback((roomId: string) => {
    setActiveRoomId(roomId);
    setRooms((prev) => prev.map((r) => (r.id === roomId ? { ...r, unread_count: 0 } : r)));
  }, []);

  const loadMore = useCallback(async () => {
    const older = OLDER_MESSAGES[activeRoomId];
    if (!older || loadingMore) return;
    setLoadingMore(true);
    await new Promise((r) => setTimeout(r, 800));
    setItems((prev) => ({
      ...prev,
      [activeRoomId]: [...older, ...(prev[activeRoomId] ?? [])],
    }));
    setRooms((prev) =>
      prev.map((r) => (r.id === activeRoomId ? { ...r, has_more: false } : r))
    );
    setLoadingMore(false);
  }, [activeRoomId, loadingMore]);

  const sendMessage = useCallback(
    (content: string, clientId: string) => {
      const msg: Message = {
        id: clientId,
        content,
        user: { id: currentUser.id, username: currentUser.username },
        room_id: activeRoomId,
        inserted_at: new Date().toISOString(),
        edited_at: null,
        attachments: [],
        client_id: clientId,
        pending: true,
      };
      setItems((prev) => ({
        ...prev,
        [activeRoomId]: [...(prev[activeRoomId] ?? []), msg],
      }));
      setTimeout(() => {
        const confirmedId = "msg-" + Math.random().toString(36).slice(2);
        setItems((prev) => ({
          ...prev,
          [activeRoomId]: (prev[activeRoomId] ?? []).map((m) =>
            "client_id" in m && m.client_id === clientId
              ? { ...m, id: confirmedId, pending: false, client_id: undefined }
              : m
          ),
        }));
        // Simulate read_receipts:updated
        setReadReceipts((prev) => ({ ...prev, [confirmedId]: [] }));
      }, 450);
    },
    [activeRoomId, currentUser]
  );

  const editMessage = useCallback(
    (messageId: string, content: string) => {
      setItems((prev) => ({
        ...prev,
        [activeRoomId]: (prev[activeRoomId] ?? []).map((m) =>
          m.id === messageId && "content" in m
            ? { ...m, content, edited_at: new Date().toISOString() }
            : m
        ),
      }));
      setEditingMessage(null);
      addToast("success", "Mensagem editada.");
    },
    [activeRoomId, addToast]
  );

  // Contract: message:deleted → mark as deleted, do NOT remove from list
  const deleteMessage = useCallback(
    (messageId: string) => {
      setItems((prev) => ({
        ...prev,
        [activeRoomId]: (prev[activeRoomId] ?? []).map((m) =>
          m.id === messageId && "content" in m ? { ...m, deleted: true, content: "" } : m
        ),
      }));
      addToast("info", "Mensagem excluída.");
    },
    [activeRoomId, addToast]
  );

  const startTyping = useCallback(() => {
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
    typingTimerRef.current = setTimeout(stopTyping, 3000);
  }, []);

  const stopTyping = useCallback(() => {
    if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
  }, []);

  const getActiveTreatment = useCallback(
    () => rooms.find((r) => r.id === activeRoomId)?.treatment ?? null,
    [rooms, activeRoomId]
  );

  // Contract section 24: treatment state is driven ONLY by broadcasts
  // We simulate: send command → wait for mock "broadcast" → update state
  const broadcastTreatmentUpdate = useCallback(
    (update: Partial<import("../types").Treatment>, sysText: string, event: SystemMessage["event"], actor: string, detail?: string) => {
      setRooms((prev) =>
        prev.map((r) =>
          r.id === activeRoomId && r.treatment
            ? { ...r, treatment: { ...r.treatment, ...update } }
            : r
        )
      );
      const sysMsg: SystemMessage = {
        id: "sys-" + Math.random().toString(36).slice(2),
        kind: "system",
        event,
        text: sysText,
        room_id: activeRoomId,
        inserted_at: new Date().toISOString(),
      };
      setItems((prev) => ({
        ...prev,
        [activeRoomId]: [...(prev[activeRoomId] ?? []), sysMsg],
      }));
      setAuditLog((prev) => [
        ...prev,
        {
          id: "audit-" + Math.random().toString(36).slice(2),
          event,
          actor,
          timestamp: new Date().toISOString(),
          detail,
        },
      ]);
    },
    [activeRoomId]
  );

  const assignToMe = useCallback(async () => {
    const t = getActiveTreatment();
    if (!t || commandPending) return;
    if (t.assigned_agent_id && t.assigned_agent_id !== currentUser.id) {
      addToast("error", "Já atribuída", "Esta tratativa já está com outro agente.");
      return;
    }
    setCommandPending(true);
    await new Promise((r) => setTimeout(r, 650));
    // Simulate broadcast: treatment:agent_assigned
    broadcastTreatmentUpdate(
      { status: "in_progress", assigned_agent_id: currentUser.id, assigned_at: new Date().toISOString() },
      `${currentUser.username} assumiu a tratativa`,
      "treatment:agent_assigned",
      currentUser.username,
      "Assumiu a tratativa"
    );
    addToast("success", "Tratativa assumida.");
    setCommandPending(false);
  }, [getActiveTreatment, commandPending, currentUser, broadcastTreatmentUpdate, addToast]);

  const resolveTreatment = useCallback(async () => {
    const t = getActiveTreatment();
    if (!t || commandPending) return;
    setCommandPending(true);
    await new Promise((r) => setTimeout(r, 650));
    broadcastTreatmentUpdate(
      { status: "resolved", resolved_by_id: currentUser.id, resolved_at: new Date().toISOString() },
      `${currentUser.username} resolveu a tratativa`,
      "treatment:resolved",
      currentUser.username,
      "Resolveu a tratativa"
    );
    addToast("success", "Tratativa resolvida.");
    setCommandPending(false);
  }, [getActiveTreatment, commandPending, currentUser, broadcastTreatmentUpdate, addToast]);

  const reopenTreatment = useCallback(async () => {
    const t = getActiveTreatment();
    if (!t || commandPending) return;
    setCommandPending(true);
    await new Promise((r) => setTimeout(r, 650));
    broadcastTreatmentUpdate(
      { status: "in_progress", resolved_by_id: null, resolved_at: null },
      `${currentUser.username} reabriu a tratativa`,
      "treatment:reopened",
      currentUser.username,
      "Reabriu a tratativa"
    );
    addToast("success", "Tratativa reaberta.");
    setCommandPending(false);
  }, [getActiveTreatment, commandPending, currentUser, broadcastTreatmentUpdate, addToast]);

  const transferTreatment = useCallback(
    async (targetAgentId: string) => {
      const t = getActiveTreatment();
      if (!t || commandPending) return;
      const targetAgent = MOCK_AGENTS.find((a) => a.id === targetAgentId);
      setCommandPending(true);
      await new Promise((r) => setTimeout(r, 850));
      broadcastTreatmentUpdate(
        { status: "in_progress", assigned_agent_id: targetAgentId, assigned_at: new Date().toISOString() },
        `${currentUser.username} transferiu para ${targetAgent?.username ?? targetAgentId}`,
        "treatment:transferred",
        currentUser.username,
        `Transferiu para ${targetAgent?.username ?? targetAgentId}`
      );
      addToast("success", "Tratativa transferida.");
      setCommandPending(false);
    },
    [getActiveTreatment, commandPending, currentUser, broadcastTreatmentUpdate, addToast]
  );

  const activeRoom = rooms.find((r) => r.id === activeRoomId);
  const activeItems = items[activeRoomId] ?? [];
  const activePresence = presence[activeRoomId] ?? [];
  const typingUsers = activePresence.filter((u) => u.id !== currentUser.id && u.typing);

  return {
    connectionState,
    currentUser,
    rooms,
    activeRoom,
    activeRoomId,
    selectRoom,
    activeItems,
    activePresence,
    typingUsers,
    readReceipts,
    editingMessage,
    setEditingMessage,
    commandPending,
    toasts,
    dismissToast,
    loadingMore,
    loadMore,
    auditLog,
    getActiveTreatment,
    sendMessage,
    editMessage,
    deleteMessage,
    startTyping,
    stopTyping,
    assignToMe,
    resolveTreatment,
    reopenTreatment,
    transferTreatment,
  };
}
