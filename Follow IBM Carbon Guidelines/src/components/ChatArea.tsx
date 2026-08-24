import { useEffect, useRef } from "react";
import type { ChatItem, Message, PresenceUser, ReadReceiptsMap, User } from "../types";
import MessageItem from "./MessageItem";
import MessageInput from "./MessageInput";

interface Props {
  items: ChatItem[];
  currentUser: User;
  typingUsers: PresenceUser[];
  readReceipts: ReadReceiptsMap;
  editingMessage: Message | null;
  hasMore: boolean;
  loadingMore: boolean;
  onLoadMore: () => void;
  onSend: (content: string, clientId: string) => void;
  onEdit: (msg: Message) => void;
  onSaveEdit: (id: string, content: string) => void;
  onDelete: (id: string) => void;
  onCancelEdit: () => void;
  onStartTyping: () => void;
  onStopTyping: () => void;
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  const today = new Date();
  const yesterday = new Date(today.getTime() - 86400000);
  if (d.toDateString() === today.toDateString()) return "Hoje";
  if (d.toDateString() === yesterday.toDateString()) return "Ontem";
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "long", year: "numeric" });
}

function getItemDate(item: ChatItem): string {
  const iso = "kind" in item ? item.inserted_at : item.inserted_at;
  return formatDate(iso);
}

function groupItemsByDate(items: ChatItem[]): Array<{ date: string; items: ChatItem[] }> {
  const groups: Array<{ date: string; items: ChatItem[] }> = [];
  for (const item of items) {
    const date = getItemDate(item);
    const last = groups[groups.length - 1];
    if (last && last.date === date) {
      last.items.push(item);
    } else {
      groups.push({ date, items: [item] });
    }
  }
  return groups;
}

function SkeletonMessage() {
  return (
    <div style={{ display: "flex", gap: 10, padding: "8px 16px", alignItems: "flex-start" }}>
      <div
        style={{
          width: 32,
          height: 32,
          borderRadius: "50%",
          background: "#e0e0e0",
          flexShrink: 0,
          animation: "skeleton-pulse 1.4s ease-in-out infinite",
        }}
      />
      <div style={{ flex: 1 }}>
        <div
          style={{
            height: 12,
            width: "30%",
            background: "#e0e0e0",
            marginBottom: 6,
            animation: "skeleton-pulse 1.4s ease-in-out 0.1s infinite",
          }}
        />
        <div
          style={{
            height: 14,
            width: "75%",
            background: "#e0e0e0",
            animation: "skeleton-pulse 1.4s ease-in-out 0.2s infinite",
          }}
        />
      </div>
      <style>{`
        @keyframes skeleton-pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
      `}</style>
    </div>
  );
}

export default function ChatArea({
  items,
  currentUser,
  typingUsers,
  readReceipts,
  editingMessage,
  hasMore,
  loadingMore,
  onLoadMore,
  onSend,
  onEdit,
  onSaveEdit,
  onDelete,
  onCancelEdit,
  onStartTyping,
  onStopTyping,
}: Props) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const prevLenRef = useRef(items.length);

  useEffect(() => {
    if (items.length > prevLenRef.current) {
      bottomRef.current?.scrollIntoView({ behavior: "smooth" });
    }
    prevLenRef.current = items.length;
  }, [items.length]);

  const groups = groupItemsByDate(items);
  const lastGroup = groups[groups.length - 1];
  const lastItem = lastGroup?.items[lastGroup.items.length - 1];
  const lastItemId = lastItem?.id;

  return (
    <div
      style={{
        flex: 1,
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
        background: "#ffffff",
      }}
    >
      {/* Message scroll area */}
      <div style={{ flex: 1, overflowY: "auto", display: "flex", flexDirection: "column" }}>
        {/* Load more — GET /messages?before=&limit= */}
        {hasMore && (
          <div style={{ display: "flex", justifyContent: "center", padding: "12px 0 4px" }}>
            <button
              onClick={onLoadMore}
              disabled={loadingMore}
              style={{
                background: "transparent",
                border: "1px solid #0f62fe",
                color: "#0f62fe",
                fontFamily: "var(--font-sans)",
                fontSize: 12,
                padding: "6px 16px",
                cursor: loadingMore ? "not-allowed" : "pointer",
                display: "flex",
                alignItems: "center",
                gap: 6,
                transition: "background 70ms",
              }}
            >
              {loadingMore ? (
                <>
                  <InlineSpinner />
                  Carregando...
                </>
              ) : (
                "Carregar mensagens anteriores"
              )}
            </button>
          </div>
        )}

        {loadingMore && (
          <>
            <SkeletonMessage />
            <SkeletonMessage />
            <SkeletonMessage />
          </>
        )}

        {items.length === 0 && !loadingMore && (
          <div
            style={{
              flex: 1,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              color: "#8d8d8d",
              fontSize: 14,
              gap: 8,
              padding: 48,
            }}
          >
            <span
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: 32,
                color: "#c6c6c6",
                fontWeight: 300,
              }}
            >
              [ ]
            </span>
            <span style={{ color: "#525252", fontWeight: 500 }}>Nenhuma mensagem</span>
            <span
              style={{
                fontSize: 12,
                fontFamily: "var(--font-mono)",
                color: "#a8a8a8",
              }}
            >
              Seja o primeiro a enviar uma mensagem nesta sala.
            </span>
          </div>
        )}

        {groups.map(({ date, items: groupItems }) => (
          <div key={date}>
            {/* Carbon date separator */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 12,
                padding: "12px 16px 6px",
              }}
            >
              <div style={{ flex: 1, height: 1, background: "#e0e0e0" }} />
              <span
                style={{
                  fontSize: 11,
                  color: "#8d8d8d",
                  fontFamily: "var(--font-mono)",
                  whiteSpace: "nowrap",
                  padding: "2px 8px",
                  background: "#f4f4f4",
                }}
              >
                {date}
              </span>
              <div style={{ flex: 1, height: 1, background: "#e0e0e0" }} />
            </div>

            {groupItems.map((item) => {
              const readBy = ("id" in item && !(("kind" in item)))
                ? (readReceipts[item.id] ?? []).filter((id) => id !== currentUser.id)
                : [];
              return (
                <MessageItem
                  key={item.id}
                  item={item}
                  currentUser={currentUser}
                  onEdit={onEdit}
                  onDelete={onDelete}
                  readBy={readBy}
                  isLast={item.id === lastItemId}
                />
              );
            })}
          </div>
        ))}

        <div ref={bottomRef} style={{ height: 4 }} />
      </div>

      {/* Typing indicator — driven by Presence diff */}
      <div style={{ minHeight: 22, padding: "0 16px 2px" }}>
        {typingUsers.length > 0 && (
          <div
            style={{
              fontSize: 12,
              color: "#6f6f6f",
              fontFamily: "var(--font-mono)",
              display: "flex",
              alignItems: "center",
              gap: 6,
            }}
          >
            <TypingDots />
            <span>
              {typingUsers.map((u) => u.username).join(", ")}{" "}
              {typingUsers.length === 1 ? "está digitando" : "estão digitando"}
            </span>
          </div>
        )}
      </div>

      {/* Input */}
      <MessageInput
        editingMessage={editingMessage}
        onSend={onSend}
        onSaveEdit={onSaveEdit}
        onCancelEdit={onCancelEdit}
        onStartTyping={onStartTyping}
        onStopTyping={onStopTyping}
      />
    </div>
  );
}

function TypingDots() {
  return (
    <span style={{ display: "inline-flex", gap: 2, alignItems: "center" }}>
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          style={{
            width: 4,
            height: 4,
            borderRadius: "50%",
            background: "#8d8d8d",
            animation: `typing-dot 1.2s ${i * 0.2}s ease-in-out infinite`,
          }}
        />
      ))}
      <style>{`
        @keyframes typing-dot {
          0%, 60%, 100% { transform: translateY(0); opacity: 0.35; }
          30% { transform: translateY(-3px); opacity: 1; }
        }
      `}</style>
    </span>
  );
}

function InlineSpinner() {
  return (
    <span
      style={{
        width: 12,
        height: 12,
        border: "2px solid #e0e0e0",
        borderTopColor: "#0f62fe",
        borderRadius: "50%",
        display: "inline-block",
        animation: "spin 0.7s linear infinite",
        flexShrink: 0,
      }}
    >
      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </span>
  );
}
