import { useState } from "react";
import { Button } from "@carbon/react";
import { pkg, SidePanel } from "@carbon/ibm-products";
import { useMockSocket } from "./hooks/useMockSocket";
import ChatSidebar from "./components/ChatSidebar";
import ChatArea from "./components/ChatArea";
import TreatmentPanel from "./components/TreatmentPanel";
import type { Toast } from "./types";

pkg.component.SidePanel = true;

const CONNECTION_META: Record<string, { label: string; dot: string; error: boolean }> = {
  idle:         { label: "Aguardando",        dot: "#8d8d8d", error: false },
  connecting:   { label: "Conectando...",     dot: "#f1c21b", error: false },
  connected:    { label: "Conectado",         dot: "#24a148", error: false },
  error:        { label: "Erro de conexão",   dot: "#fa4d56", error: true  },
  recovering:   { label: "Reconectando...",   dot: "#f1c21b", error: true  },
  disconnected: { label: "Desconectado",      dot: "#fa4d56", error: true  },
};

function ToastNotification({ toast, onDismiss }: { toast: Toast; onDismiss: (id: string) => void }) {
  const COLOR: Record<Toast["type"], { border: string; bg: string; text: string; icon: string }> = {
    success: { border: "#42be65", bg: "#022d0d", text: "#a7f0ba", icon: "✓" },
    error:   { border: "#fa4d56", bg: "#2d0709", text: "#ffd7d9", icon: "✕" },
    info:    { border: "#4589ff", bg: "#001d6c", text: "#d0e2ff", icon: "ℹ" },
    warning: { border: "#f1c21b", bg: "#302a00", text: "#fdd13a", icon: "⚠" },
  };
  const c = COLOR[toast.type];
  return (
    <div
      style={{
        background: c.bg,
        borderLeft: `3px solid ${c.border}`,
        color: c.text,
        padding: "12px 40px 12px 16px",
        minWidth: 260,
        maxWidth: 380,
        boxShadow: "0 4px 12px rgba(0,0,0,0.45)",
        fontFamily: "var(--font-sans)",
        position: "relative",
        animation: "toast-in 180ms ease-out",
      }}
    >
      <div style={{ display: "flex", gap: 8, alignItems: "flex-start" }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 14, flexShrink: 0 }}>{c.icon}</span>
        <div>
          <div style={{ fontSize: 14, fontWeight: 500, lineHeight: "20px" }}>{toast.title}</div>
          {toast.subtitle && (
            <div style={{ fontSize: 12, marginTop: 2, opacity: 0.8, lineHeight: "18px" }}>
              {toast.subtitle}
            </div>
          )}
        </div>
      </div>
      <button
        onClick={() => onDismiss(toast.id)}
        style={{
          position: "absolute",
          top: 8,
          right: 8,
          background: "none",
          border: "none",
          color: c.text,
          cursor: "pointer",
          fontSize: 14,
          opacity: 0.6,
          padding: 4,
          lineHeight: 1,
        }}
      >
        ✕
      </button>
      <style>{`@keyframes toast-in { from { transform: translateX(20px); opacity: 0; } to { transform: none; opacity: 1; } }`}</style>
    </div>
  );
}

export default function App() {
  const {
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
  } = useMockSocket();
  const [rightPanelOpen, setRightPanelOpen] = useState(true);

  const treatment = getActiveTreatment();
  const connMeta = CONNECTION_META[connectionState] ?? CONNECTION_META.idle;
  const isError = connMeta.error;

  const initials = currentUser.username
    .split(".")
    .map((p) => p[0]?.toUpperCase() ?? "")
    .join("")
    .slice(0, 2);

  return (
    <div
      style={{
        height: "100vh",
        display: "flex",
        flexDirection: "column",
        fontFamily: "var(--font-sans)",
        overflow: "hidden",
        background: "#161616",
      }}
    >
      {/* Carbon UI Shell header */}
      <header
        style={{
          height: 48,
          background: "#161616",
          display: "flex",
          alignItems: "center",
          padding: "0 0 0 16px",
          flexShrink: 0,
          borderBottom: "1px solid #393939",
          gap: 0,
        }}
      >
        {/* Product name */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 10,
            paddingRight: 16,
            borderRight: "1px solid #393939",
            height: "100%",
          }}
        >
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden>
            <rect width="20" height="20" fill="#0f62fe" />
            <path d="M5 10h10M10 5v10" stroke="white" strokeWidth="1.5" />
          </svg>
          <span
            style={{
              color: "#ffffff",
              fontSize: 14,
              fontWeight: 600,
              letterSpacing: "0.005em",
              whiteSpace: "nowrap",
            }}
          >
            Chat Suporte
          </span>
        </div>

        {/* Sub-product label */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            height: "100%",
            padding: "0 16px",
            borderRight: "1px solid #393939",
          }}
        >
          <span style={{ color: "#8d8d8d", fontSize: 12, fontFamily: "var(--font-mono)" }}>
            Logística
          </span>
        </div>

        <div style={{ flex: 1 }} />

        {/* Connection status */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 6,
            padding: "0 16px",
            height: "100%",
            borderLeft: "1px solid #393939",
          }}
        >
          <span
            style={{
              width: 6,
              height: 6,
              borderRadius: "50%",
              background: connMeta.dot,
              flexShrink: 0,
            }}
          />
          <span style={{ color: "#8d8d8d", fontSize: 11, fontFamily: "var(--font-mono)" }}>
            {connMeta.label}
          </span>
        </div>

        {/* User chip */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            padding: "0 16px",
            height: "100%",
            borderLeft: "1px solid #393939",
          }}
        >
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: "50%",
              background: "#0f62fe",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "#fff",
              fontSize: 11,
              fontFamily: "var(--font-mono)",
              fontWeight: 500,
              flexShrink: 0,
            }}
          >
            {initials}
          </div>
          <div>
            <div style={{ color: "#ffffff", fontSize: 12, lineHeight: "16px" }}>
              {currentUser.username}
            </div>
            <div style={{ color: "#6f6f6f", fontSize: 11, fontFamily: "var(--font-mono)", lineHeight: "14px" }}>
              {currentUser.role === "logistics_agent" ? "agente · logística" : currentUser.role}
            </div>
          </div>
        </div>
      </header>

      {/* Connection error — Carbon inline notification */}
      {isError && (
        <div
          style={{
            background: "#2d0709",
            borderBottom: "1px solid #da1e28",
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "8px 16px",
            flexShrink: 0,
          }}
        >
          <span style={{ color: "#ff8389", fontSize: 14, flexShrink: 0 }}>✕</span>
          <span style={{ color: "#ffd7d9", fontSize: 13 }}>
            <strong>Conexão interrompida.</strong> O socket está em estado{" "}
            <code style={{ fontFamily: "var(--font-mono)", fontSize: 12 }}>{connectionState}</code>.
            As mensagens serão retransmitidas quando a conexão for restabelecida.
          </span>
        </div>
      )}

      {/* Main layout */}
      <div id="chat-page-content" style={{ flex: 1, display: "flex", overflow: "hidden" }}>
        {/* Sidebar */}
        <ChatSidebar
          rooms={rooms}
          activeRoomId={activeRoomId}
          currentUser={currentUser}
          onSelectRoom={selectRoom}
        />

        {/* Chat area */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
          {/* Room header */}
          <div
            style={{
              height: 48,
              background: "#ffffff",
              borderBottom: "1px solid #e0e0e0",
              display: "flex",
              alignItems: "center",
              padding: "0 16px",
              gap: 12,
              flexShrink: 0,
            }}
          >
            <div style={{ flex: 1, minWidth: 0 }}>
              <span
                style={{
                  fontSize: 14,
                  fontWeight: 600,
                  color: "#161616",
                  lineHeight: "20px",
                }}
              >
                {activeRoom?.name ?? "—"}
              </span>
              <span
                style={{
                  marginLeft: 10,
                  fontSize: 11,
                  color: "#8d8d8d",
                  fontFamily: "var(--font-mono)",
                }}
              >
                room:{activeRoomId.slice(0, 8)}...
              </span>
            </div>

            {/* Presence pills */}
            <div style={{ display: "flex", alignItems: "center", gap: 6, flexShrink: 0 }}>
              {activePresence.map((u) => (
                <div
                  key={u.id}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 4,
                    padding: "2px 8px",
                    background: u.id === currentUser.id ? "#edf5ff" : "#f4f4f4",
                    border: `1px solid ${u.id === currentUser.id ? "#d0e2ff" : "#e0e0e0"}`,
                  }}
                  title={`Entrou: ${new Date(u.joined_at).toLocaleTimeString("pt-BR")}`}
                >
                  <span
                    style={{
                      width: 6,
                      height: 6,
                      borderRadius: "50%",
                      background: u.typing ? "#f1c21b" : "#24a148",
                      flexShrink: 0,
                      transition: "background 200ms",
                    }}
                  />
                  <span
                    style={{
                      fontSize: 11,
                      fontFamily: "var(--font-mono)",
                      color: u.id === currentUser.id ? "#0043ce" : "#525252",
                    }}
                  >
                    {u.username}
                  </span>
                </div>
              ))}
              {activePresence.length === 0 && (
                <span style={{ fontSize: 11, color: "#8d8d8d", fontFamily: "var(--font-mono)" }}>
                  Nenhum usuário online
                </span>
              )}
            </div>
            <Button kind="ghost" size="sm" onClick={() => setRightPanelOpen(true)}>
              Tratativa
            </Button>
          </div>

          {/* Messages */}
          <ChatArea
            items={activeItems}
            currentUser={currentUser}
            typingUsers={typingUsers}
            readReceipts={readReceipts}
            editingMessage={editingMessage}
            hasMore={activeRoom?.has_more ?? false}
            loadingMore={loadingMore}
            onLoadMore={loadMore}
            onSend={sendMessage}
            onEdit={setEditingMessage}
            onSaveEdit={editMessage}
            onDelete={deleteMessage}
            onCancelEdit={() => setEditingMessage(null)}
            onStartTyping={startTyping}
            onStopTyping={stopTyping}
          />
        </div>

      </div>

      <SidePanel
        open={rightPanelOpen}
        onRequestClose={() => setRightPanelOpen(false)}
        closeIconDescription="Fechar tratativa"
        labelText="Tratativa"
        title="Detalhes do pedido"
        placement="right"
        size="md"
        slideIn
        selectorPageContent="#chat-page-content"
      >
        <TreatmentPanel
          treatment={treatment}
          currentUser={currentUser}
          auditLog={auditLog}
          onAssignToMe={assignToMe}
          onResolve={resolveTreatment}
          onReopen={reopenTreatment}
          onTransfer={transferTreatment}
          pending={commandPending}
        />
      </SidePanel>

      {/* Toast stack — bottom-right */}
      <div
        style={{
          position: "fixed",
          bottom: 16,
          right: 16,
          display: "flex",
          flexDirection: "column-reverse",
          gap: 8,
          zIndex: 9999,
          pointerEvents: "none",
        }}
      >
        {toasts.map((t) => (
          <div key={t.id} style={{ pointerEvents: "auto" }}>
            <ToastNotification toast={t} onDismiss={dismissToast} />
          </div>
        ))}
      </div>
    </div>
  );
}
