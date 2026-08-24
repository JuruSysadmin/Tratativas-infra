import { useState, useRef, useEffect } from "react";
import type { Message, SystemMessage, ChatItem, User } from "../types";

interface Props {
  item: ChatItem;
  currentUser: User;
  onEdit: (msg: Message) => void;
  onDelete: (id: string) => void;
  readBy: string[];
  isLast: boolean;
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
}

function getInitials(username: string): string {
  return username
    .split(".")
    .map((p) => p[0]?.toUpperCase() ?? "")
    .join("")
    .slice(0, 2);
}

const AVATAR_PALETTE = ["#0f62fe", "#8a3ffc", "#009d9a", "#005d5d", "#a56eff", "#1192e8"];

function avatarColor(userId: string): string {
  let h = 0;
  for (let i = 0; i < userId.length; i++) h = (h * 31 + userId.charCodeAt(i)) >>> 0;
  return AVATAR_PALETTE[h % AVATAR_PALETTE.length];
}

const SYSTEM_EVENT_LABEL: Record<string, string> = {
  "treatment:agent_assigned": "Tratativa assumida",
  "treatment:transferred": "Tratativa transferida",
  "treatment:resolved": "Tratativa resolvida",
  "treatment:reopened": "Tratativa reaberta",
  "treatment:unassigned": "Tratativa liberada",
  "room:joined": "Entrou na sala",
};

const SYSTEM_EVENT_ICON: Record<string, string> = {
  "treatment:agent_assigned": "→",
  "treatment:transferred": "⇄",
  "treatment:resolved": "✓",
  "treatment:reopened": "↺",
  "treatment:unassigned": "↩",
  "room:joined": "·",
};

// Carbon overflow menu component
function OverflowMenu({
  onEdit,
  onDelete,
}: {
  onEdit: () => void;
  onDelete: () => void;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  return (
    <div ref={ref} style={{ position: "relative", flexShrink: 0 }}>
      <button
        onClick={() => setOpen((v) => !v)}
        title="Ações"
        style={{
          width: 32,
          height: 32,
          background: open ? "#e0e0e0" : "transparent",
          border: "none",
          cursor: "pointer",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 16,
          color: "#525252",
          transition: "background 70ms",
        }}
      >
        ⋯
      </button>
      {open && (
        <div
          style={{
            position: "absolute",
            top: "100%",
            right: 0,
            background: "#ffffff",
            border: "1px solid #e0e0e0",
            boxShadow: "0 4px 8px rgba(0,0,0,0.16)",
            zIndex: 100,
            minWidth: 144,
          }}
        >
          <OverflowItem
            label="Editar mensagem"
            onClick={() => { onEdit(); setOpen(false); }}
          />
          <div style={{ borderTop: "1px solid #e0e0e0" }} />
          <OverflowItem
            label="Excluir mensagem"
            danger
            onClick={() => { onDelete(); setOpen(false); }}
          />
        </div>
      )}
    </div>
  );
}

function OverflowItem({
  label,
  onClick,
  danger,
}: {
  label: string;
  onClick: () => void;
  danger?: boolean;
}) {
  const [hov, setHov] = useState(false);
  return (
    <button
      onClick={onClick}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display: "block",
        width: "100%",
        textAlign: "left",
        padding: "10px 16px",
        background: hov ? (danger ? "#fff1f1" : "#f4f4f4") : "transparent",
        border: "none",
        cursor: "pointer",
        fontSize: 14,
        fontFamily: "var(--font-sans)",
        color: danger ? "#da1e28" : "#161616",
        transition: "background 70ms",
      }}
    >
      {label}
    </button>
  );
}

export default function MessageItem({ item, currentUser, onEdit, onDelete, readBy, isLast }: Props) {
  const [hovered, setHovered] = useState(false);

  // System message rendering
  if ("kind" in item && item.kind === "system") {
    return (
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "4px 16px",
          margin: "2px 0",
        }}
      >
        <div style={{ flex: 1, height: 1, background: "#f4f4f4" }} />
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 6,
            padding: "2px 8px",
            background: "#f4f4f4",
            flexShrink: 0,
          }}
        >
          <span style={{ fontSize: 11, color: "#8d8d8d", fontFamily: "var(--font-mono)" }}>
            {SYSTEM_EVENT_ICON[item.event] ?? "·"}
          </span>
          <span style={{ fontSize: 11, color: "#6f6f6f", fontFamily: "var(--font-mono)" }}>
            {item.text}
          </span>
          <span style={{ fontSize: 10, color: "#a8a8a8", fontFamily: "var(--font-mono)" }}>
            {formatTime(item.inserted_at)}
          </span>
        </div>
        <div style={{ flex: 1, height: 1, background: "#f4f4f4" }} />
      </div>
    );
  }

  const msg = item as Message;
  const isOwn = msg.user.id === currentUser.id;
  const isDeleted = msg.deleted === true;
  const initials = getInitials(msg.user.username);
  const bgColor = avatarColor(msg.user.id);
  const canAct = isOwn && !msg.pending && !isDeleted;

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: "flex",
        gap: 10,
        padding: "5px 16px",
        background: hovered && canAct ? "#f4f4f4" : "transparent",
        alignItems: "flex-start",
        position: "relative",
        transition: "background 70ms",
      }}
    >
      {/* Avatar */}
      <div
        style={{
          width: 32,
          height: 32,
          borderRadius: "50%",
          background: isDeleted ? "#e0e0e0" : bgColor,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: isDeleted ? "#a8a8a8" : "#fff",
          fontSize: 11,
          fontFamily: "var(--font-mono)",
          fontWeight: 500,
          flexShrink: 0,
          marginTop: 1,
        }}
      >
        {isDeleted ? "—" : initials}
      </div>

      {/* Content */}
      <div style={{ flex: 1, minWidth: 0 }}>
        {/* Header row */}
        <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginBottom: 1 }}>
          <span
            style={{
              fontSize: 14,
              fontWeight: 600,
              color: isDeleted ? "#a8a8a8" : isOwn ? "#0f62fe" : "#161616",
              lineHeight: "18px",
            }}
          >
            {isDeleted ? msg.user.username : msg.user.username}
          </span>
          <span
            style={{
              fontSize: 12,
              color: "#8d8d8d",
              fontFamily: "var(--font-mono)",
              lineHeight: "16px",
            }}
          >
            {formatTime(msg.inserted_at)}
          </span>
          {msg.edited_at && !isDeleted && (
            <span
              style={{
                fontSize: 11,
                color: "#a8a8a8",
                fontFamily: "var(--font-mono)",
                fontStyle: "italic",
              }}
            >
              (editado)
            </span>
          )}
          {msg.pending && (
            <span style={{ fontSize: 11, color: "#8d8d8d", fontFamily: "var(--font-mono)" }}>
              enviando...
            </span>
          )}
        </div>

        {/* Body */}
        {isDeleted ? (
          <div
            style={{
              fontSize: 14,
              color: "#a8a8a8",
              fontStyle: "italic",
              lineHeight: "20px",
              display: "flex",
              alignItems: "center",
              gap: 6,
            }}
          >
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 12 }}>🗑</span>
            Esta mensagem foi excluída
          </div>
        ) : (
          <div
            style={{
              fontSize: 14,
              color: "#161616",
              lineHeight: "20px",
              wordBreak: "break-word",
              opacity: msg.pending ? 0.55 : 1,
            }}
          >
            {msg.content}
          </div>
        )}

        {/* Attachments */}
        {!isDeleted && msg.attachments.length > 0 && (
          <div style={{ marginTop: 6, display: "flex", flexDirection: "column", gap: 4 }}>
            {msg.attachments.map((att) => (
              <div
                key={att.id}
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 8,
                  background: "#edf5ff",
                  padding: "6px 10px",
                  maxWidth: 280,
                  borderLeft: "3px solid #0f62fe",
                }}
              >
                <span style={{ fontSize: 14, color: "#0f62fe" }}>📎</span>
                <span style={{ fontSize: 12, color: "#0043ce", fontFamily: "var(--font-mono)" }}>
                  {att.filename}
                </span>
              </div>
            ))}
          </div>
        )}

        {/* Read receipts for last own message */}
        {isLast && isOwn && !isDeleted && (
          <div
            style={{
              marginTop: 3,
              fontSize: 11,
              color: "#8d8d8d",
              fontFamily: "var(--font-mono)",
              display: "flex",
              alignItems: "center",
              gap: 4,
            }}
          >
            {readBy.length > 0 ? (
              <>
                <span style={{ color: "#24a148" }}>✓✓</span>
                <span>Lido por {readBy.join(", ")}</span>
              </>
            ) : msg.pending ? null : (
              <>
                <span style={{ color: "#a8a8a8" }}>✓</span>
                <span>Entregue</span>
              </>
            )}
          </div>
        )}
      </div>

      {/* Carbon overflow menu — only own, not deleted, not pending */}
      {hovered && canAct && (
        <div style={{ alignSelf: "flex-start", marginTop: 0 }}>
          <OverflowMenu
            onEdit={() => onEdit(msg)}
            onDelete={() => onDelete(msg.id)}
          />
        </div>
      )}
    </div>
  );
}
