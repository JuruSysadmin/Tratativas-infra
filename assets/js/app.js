import "phoenix_html"
import "../css/app.css"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import MarkRead from "./hooks/mark_read"
import MentionCombobox from "./hooks/mention_combobox"
import MessageLoading from "./hooks/message_loading"
import NotificationSound from "./hooks/notification_sound"
import ConnectionStatus from "./hooks/connection_status"
import MessageOutbox from "./hooks/message_outbox"
import PendingMessages from "./hooks/pending_messages"

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

let Hooks = {MarkRead, MentionCombobox, MessageLoading, NotificationSound, ConnectionStatus, MessageOutbox, PendingMessages}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

function publishConnectionState(state) {
  window.chatConnectionState = state
  window.dispatchEvent(new CustomEvent("chat:connection-state", {detail: {state}}))
}

let hasConnected = false

liveSocket.socket.onOpen(() => {
  publishConnectionState(hasConnected ? "reconnected" : "connected")
  hasConnected = true
})
liveSocket.socket.onError(() => publishConnectionState("reconnecting"))
liveSocket.socket.onClose(() => publishConnectionState("disconnected"))

liveSocket.connect()

window.addEventListener("phx:scroll_to_bottom", () => {
  window.requestAnimationFrame(() => {
    const messages = document.getElementById("messages-list")

    if (messages) {
      messages.scrollTop = messages.scrollHeight
    }
  })
})

window.addEventListener("phx:scroll_to_message", ({detail: {id}}) => {
  window.requestAnimationFrame(() => {
    const message = document.getElementById(id)

    if (message) {
      message.scrollIntoView({behavior: "smooth", block: "center"})
      message.focus({preventScroll: true})
    }
  })
})

window.liveSocket = liveSocket
