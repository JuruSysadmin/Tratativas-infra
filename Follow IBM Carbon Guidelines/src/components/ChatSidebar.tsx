import type { Room, User } from "../types";

const STATUS_LABEL: Record<string, string> = {
  open: "Aberto",
  in_progress: "Em andamento",
  resolved: "Resolvido",
  closed: "Fechado",
};

const STATUS_COLOR: Record<string, string> = {
  open: "#0f62fe",
  in_progress: "#f1c21b",
  resolved: "#24a148",
  closed: "#8d8d8d",
};

function formatTime(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const diff = now.getTime() - d.getTime();
  if (diff < 60000) return "agora";
  if (diff < 3600000) return `${Math.floor(diff / 60000)}min`;
  if (diff < 86400000) return d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
}

interface Props {
  rooms: Room[];
  activeRoomId: string;
  currentUser: User;
  onSelectRoom: (id: string) => void;
}

export default function ChatSidebar({ rooms, activeRoomId, currentUser, onSelectRoom }: Props) {
  return (
    <aside
      style={{
        width: 280,
        minWidth: 280,
        display: "flex",
        flexDirection: "column",
        background: "#262626",
        borderRight: "1px solid #393939",
        height: "100%",
        overflow: "hidden",
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: "16px",
          borderBottom: "1px solid #393939",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          flexShrink: 0,
        }}
      >
        <div>
          <div style={{ color: "#ffffff", fontSize: 14, fontWeight: 600, lineHeight: 1.2 }}>
            Atendimentos
          </div>
          <div style={{ color: "#8d8d8d", fontSize: 12, marginTop: 2, fontFamily: "var(--font-mono)" }}>
            {currentUser.username}
          </div>
        </div>
        <span
          style={{
            background: "#0f62fe",
            color: "#fff",
            fontSize: 11,
            fontFamily: "var(--font-mono)",
            padding: "2px 6px",
          }}
        >
          {rooms.reduce((acc, r) => acc + r.unread_count, 0) > 0
            ? rooms.reduce((acc, r) => acc + r.unread_count, 0)
            : null}
        </span>
      </div>

      {/* Filter tabs */}
      <div
        style={{
          display: "flex",
          borderBottom: "1px solid #393939",
          flexShrink: 0,
        }}
      >
        {["Todos", "Meus", "Abertos"].map((tab, i) => (
          <button
            key={tab}
            style={{
              flex: 1,
              padding: "8px 0",
              background: i === 0 ? "#393939" : "transparent",
              color: i === 0 ? "#ffffff" : "#8d8d8d",
              border: "none",
              borderBottom: i === 0 ? "2px solid #0f62fe" : "2px solid transparent",
              fontSize: 12,
              cursor: "pointer",
              fontFamily: "var(--font-sans)",
            }}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Room list */}
      <div style={{ flex: 1, overflowY: "auto" }}>
        {rooms.map((room) => {
          const isActive = room.id === activeRoomId;
          const t = room.treatment;
          const status = t?.status ?? "open";
          const lastMsg = room.last_message;

          return (
            <button
              key={room.id}
              onClick={() => onSelectRoom(room.id)}
              style={{
                width: "100%",
                textAlign: "left",
                padding: "12px 16px",
                background: isActive ? "#393939" : "transparent",
                borderLeft: isActive ? "3px solid #0f62fe" : "3px solid transparent",
                border: "none",
                borderBottom: "1px solid #393939",
                cursor: "pointer",
                display: "block",
                transition: "background 70ms",
              }}
            >
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
                <div
                  style={{
                    color: "#ffffff",
                    fontSize: 14,
                    fontWeight: room.unread_count > 0 ? 600 : 400,
                    lineHeight: 1.3,
                    flex: 1,
                    marginRight: 8,
                  }}
                >
                  {room.name}
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 4, flexShrink: 0 }}>
                  {room.unread_count > 0 && (
                    <span
                      style={{
                        background: "#0f62fe",
                        color: "#fff",
                        fontSize: 10,
                        fontFamily: "var(--font-mono)",
                        padding: "1px 5px",
                        minWidth: 18,
                        textAlign: "center",
                      }}
                    >
                      {room.unread_count}
                    </span>
                  )}
                  {lastMsg && (
                    <span style={{ color: "#6f6f6f", fontSize: 11, fontFamily: "var(--font-mono)" }}>
                      {formatTime(lastMsg.inserted_at)}
                    </span>
                  )}
                </div>
              </div>

              <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 4 }}>
                <span
                  style={{
                    width: 6,
                    height: 6,
                    borderRadius: "50%",
                    background: STATUS_COLOR[status],
                    flexShrink: 0,
                    display: "inline-block",
                  }}
                />
                <span
                  style={{
                    color: "#8d8d8d",
                    fontSize: 11,
                    fontFamily: "var(--font-mono)",
                  }}
                >
                  {STATUS_LABEL[status]}
                </span>
                {t?.assigned_agent_id && (
                  <span style={{ color: "#6f6f6f", fontSize: 11, marginLeft: "auto" }}>
                    {t.assigned_agent_id === currentUser.id ? "você" : "atribuído"}
                  </span>
                )}
              </div>

              <div
                style={{
                  color: "#6f6f6f",
                  fontSize: 12,
                  marginTop: 2,
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
              >
                Pedido #{room.order_id}
              </div>
            </button>
          );
        })}
      </div>
    </aside>
  );
}
