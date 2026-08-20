const PendingMessages = {
  mounted() {
    this.storageKey = this.el.dataset.pendingStorageKey
    this.onConnectionState = ({detail: {state}}) => {
      if (state === "reconnecting" || state === "disconnected") {
        this.persistPendingMessages()
      }
    }

    window.addEventListener("chat:connection-state", this.onConnectionState)
    this.restorePendingMessages()
  },

  updated() {
    this.persistPendingMessages()
  },

  destroyed() {
    window.removeEventListener("chat:connection-state", this.onConnectionState)
  },

  restorePendingMessages() {
    if (!this.storageKey) return

    try {
      const stored = window.localStorage.getItem(this.storageKey)
      if (!stored) return

      const messages = JSON.parse(stored)
      if (Array.isArray(messages) && messages.length > 0) {
        this.pushEvent("restore_pending_messages", {messages})
      }
    } catch (_error) {
      window.localStorage.removeItem(this.storageKey)
    }
  },

  persistPendingMessages() {
    if (!this.storageKey) return

    const messages = Array.from(this.el.querySelectorAll("[data-pending-message]"))
      .map((element) => ({
        client_id: element.dataset.pendingClientId,
        content: element.querySelector(".message-content")?.textContent || ""
      }))
      .filter(({client_id, content}) => client_id && content.length > 0)

    try {
      if (messages.length === 0) {
        window.localStorage.removeItem(this.storageKey)
      } else {
        window.localStorage.setItem(this.storageKey, JSON.stringify(messages))
      }
    } catch (_error) {
      // Storage failures must not interrupt chat rendering or reconnect.
    }
  }
}

export default PendingMessages
