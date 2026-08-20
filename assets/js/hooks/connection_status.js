const RECONNECTED_DISPLAY_MS = 2500

const MESSAGES = {
  reconnecting: "Reconectando ao chat…",
  disconnected: "Conexão perdida. Tentando reconectar…",
  reconnected: "Conexão restabelecida.",
  connected: ""
}

const ConnectionStatus = {
  mounted() {
    this.hideTimer = null
    this.onConnectionState = ({detail: {state}}) => this.updateState(state)

    window.addEventListener("chat:connection-state", this.onConnectionState)
    this.updateState(window.chatConnectionState || "connected")
  },

  destroyed() {
    window.removeEventListener("chat:connection-state", this.onConnectionState)
    clearTimeout(this.hideTimer)
  },

  updateState(state) {
    const normalizedState = MESSAGES[state] ? state : "connected"

    clearTimeout(this.hideTimer)
    this.el.dataset.connectionState = normalizedState
    this.el.textContent = MESSAGES[normalizedState]
    this.el.hidden = normalizedState === "connected"

    if (normalizedState === "reconnected") {
      this.hideTimer = setTimeout(() => this.updateState("connected"), RECONNECTED_DISPLAY_MS)
    }
  }
}

export default ConnectionStatus