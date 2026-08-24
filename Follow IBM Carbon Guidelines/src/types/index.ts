export type ConnectionState =
  | "idle"
  | "connecting"
  | "connected"
  | "error"
  | "recovering"
  | "disconnected";

export type TreatmentStatus = "open" | "in_progress" | "resolved" | "closed";

export type UserRole = "logistics_agent" | "commercial" | "other";

export interface User {
  id: string;
  username: string;
  role: UserRole;
}

export interface PresenceUser {
  id: string;
  username: string;
  typing: boolean;
  joined_at: string;
}

export interface Attachment {
  id: string;
  filename: string;
  content_type: string;
  size: number;
  status: "pending" | "uploading" | "available" | "failed";
  upload_url?: string;
}

export interface Message {
  id: string;
  content: string;
  user: { id: string; username: string };
  room_id: string;
  inserted_at: string;
  edited_at: string | null;
  attachments: Attachment[];
  client_id?: string;
  pending?: boolean;
  deleted?: boolean;
}

export type TreatmentEventKind =
  | "treatment:agent_assigned"
  | "treatment:transferred"
  | "treatment:resolved"
  | "treatment:reopened"
  | "treatment:unassigned"
  | "room:joined";

export interface SystemMessage {
  id: string;
  kind: "system";
  event: TreatmentEventKind;
  text: string;
  room_id: string;
  inserted_at: string;
}

export type ChatItem = Message | SystemMessage;

export interface Treatment {
  id: string;
  order_id: number;
  room_id: string;
  status: TreatmentStatus;
  assigned_agent_id: string | null;
  assigned_at: string | null;
  resolved_by_id: string | null;
  resolved_at: string | null;
}

export interface TreatmentAuditEntry {
  id: string;
  event: TreatmentEventKind;
  actor: string;
  timestamp: string;
  detail?: string;
}

export interface Room {
  id: string;
  name: string;
  order_id: number;
  treatment: Treatment | null;
  last_message?: Message;
  unread_count: number;
  has_more: boolean;
}

export interface ReadReceiptsMap {
  [message_id: string]: string[];
}

export type Toast = {
  id: string;
  type: "success" | "error" | "info" | "warning";
  title: string;
  subtitle?: string;
};
