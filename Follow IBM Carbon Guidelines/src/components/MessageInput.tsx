import { useState, useEffect, useRef } from "react";
import type { Message } from "../types";

interface Props {
  editingMessage: Message | null;
  onSend: (content: string, clientId: string) => void;
  onSaveEdit: (id: string, content: string) => void;
  onCancelEdit: () => void;
  onStartTyping: () => void;
  onStopTyping: () => void;
}

export default function MessageInput({
  editingMessage,
  onSend,
  onSaveEdit,
  onCancelEdit,
  onStartTyping,
  onStopTyping,
}: Props) {
  const [value, setValue] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const typingRef = useRef(false);

  useEffect(() => {
    if (editingMessage) {
      setValue(editingMessage.content);
      textareaRef.current?.focus();
    }
  }, [editingMessage]);

  useEffect(() => {
    if (!editingMessage) setValue("");
  }, [editingMessage]);

  function handleChange(e: React.ChangeEvent<HTMLTextAreaElement>) {
    setValue(e.target.value);
    if (!typingRef.current) {
      typingRef.current = true;
      onStartTyping();
    }
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
    if (e.key === "Escape" && editingMessage) {
      onCancelEdit();
      setValue("");
    }
  }

  function handleBlur() {
    if (typingRef.current) {
      typingRef.current = false;
      onStopTyping();
    }
  }

  function handleSubmit() {
    const trimmed = value.trim();
    if (!trimmed) return;
    if (editingMessage) {
      onSaveEdit(editingMessage.id, trimmed);
    } else {
      const clientId = "cid-" + Date.now() + "-" + Math.random().toString(36).slice(2);
      onSend(trimmed, clientId);
    }
    setValue("");
    typingRef.current = false;
    onStopTyping();
    textareaRef.current?.focus();
  }

  const isEditing = Boolean(editingMessage);

  return (
    <div
      style={{
        borderTop: "1px solid #e0e0e0",
        background: "#ffffff",
        flexShrink: 0,
      }}
    >
      {/* Editing banner */}
      {isEditing && (
        <div
          style={{
            padding: "6px 16px",
            background: "#edf5ff",
            borderTop: "1px solid #d0e2ff",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <span style={{ fontSize: 12, color: "#0043ce", fontFamily: "var(--font-mono)" }}>
            ✏ Editando mensagem
          </span>
          <button
            onClick={() => { onCancelEdit(); setValue(""); }}
            style={{
              background: "none",
              border: "none",
              color: "#0f62fe",
              cursor: "pointer",
              fontSize: 12,
              fontFamily: "var(--font-mono)",
            }}
          >
            Cancelar (Esc)
          </button>
        </div>
      )}

      {/* Input row */}
      <div
        style={{
          display: "flex",
          alignItems: "flex-end",
          padding: "8px 16px",
          gap: 8,
        }}
      >
        {/* File attach button */}
        <button
          title="Anexar arquivo"
          style={{
            width: 40,
            height: 40,
            background: "transparent",
            border: "none",
            cursor: "pointer",
            color: "#525252",
            fontSize: 18,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexShrink: 0,
          }}
          onClick={() => {}}
        >
          📎
        </button>

        {/* Textarea */}
        <div style={{ flex: 1, position: "relative" }}>
          <textarea
            ref={textareaRef}
            value={value}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            onBlur={handleBlur}
            placeholder={isEditing ? "Editar mensagem..." : "Mensagem... (Enter para enviar, Shift+Enter para nova linha)"}
            rows={1}
            style={{
              width: "100%",
              resize: "none",
              minHeight: 40,
              maxHeight: 160,
              background: "#f4f4f4",
              border: "none",
              borderBottom: `2px solid ${isEditing ? "#0f62fe" : "#8d8d8d"}`,
              fontFamily: "var(--font-sans)",
              fontSize: 14,
              color: "#161616",
              padding: "10px 12px",
              outline: "none",
              lineHeight: 1.5,
              overflow: "auto",
              display: "block",
              transition: "border-color 70ms",
            }}
            onFocus={(e) => {
              e.currentTarget.style.borderBottomColor = "#0f62fe";
            }}
            onBlurCapture={(e) => {
              if (!isEditing) e.currentTarget.style.borderBottomColor = "#8d8d8d";
            }}
          />
        </div>

        {/* Send button */}
        <button
          onClick={handleSubmit}
          disabled={!value.trim()}
          className="cds-btn cds-btn-primary"
          style={{ flexShrink: 0, height: 40, gap: 0, padding: "0 14px" }}
        >
          {isEditing ? (
            <span style={{ fontSize: 16 }}>✓</span>
          ) : (
            <SendIcon />
          )}
        </button>
      </div>

      {/* Hint */}
      <div
        style={{
          padding: "0 16px 8px",
          fontSize: 11,
          color: "#c6c6c6",
          fontFamily: "var(--font-mono)",
        }}
      >
        Enter para enviar · Shift+Enter para nova linha
      </div>
    </div>
  );
}

function SendIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
      <path d="M13.72 6.68L2.72.68A1 1 0 001.3 1.92l2.07 5.08H10v1H3.37L1.3 13.08a1 1 0 001.42 1.24l11-6a1 1 0 000-1.64z" />
    </svg>
  );
}
