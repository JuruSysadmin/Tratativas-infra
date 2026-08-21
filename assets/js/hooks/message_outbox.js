const MessageOutbox = {
  mounted() {
    this.storageKey = this.el.dataset.outboxStorageKey
    this.input = this.el.querySelector('[name="text"]')
    this.submitButton = null
    this.activeIndex = -1

    this.onInput = () => {
      if (this.submitButton) this.submitButton.disabled = !this.input?.value.trim()
    }

    this.onSubmit = (event) => {
      const content = this.input?.value.trim()
      if (!content) return

      event.preventDefault()
      event.stopPropagation()
      event.stopImmediatePropagation()

      const message = {client_id: this.generateClientId(), content}
      this.store(this.messages().concat(message))
      this.input.value = ""
      this.onInput()
      this.pushEvent("send_message", {client_id: message.client_id, text: message.content})
    }

    this.onKeydown = (event) => {
      if (event.target !== this.input) return

      const options = this.options()

      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        if (options.length === 0) return
        event.preventDefault()
        this.moveActive(event.key === "ArrowDown" ? 1 : -1)
      } else if (event.key === "Enter" && this.activeIndex >= 0 && options[this.activeIndex]) {
        event.preventDefault()
        options[this.activeIndex].click()
      } else if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
        event.preventDefault()
        this.el.requestSubmit()
      } else if (event.key === "Escape" && options.length > 0) {
        event.preventDefault()
        this.clearActive()
        this.pushEvent("dismiss_mentions", {})
      }
    }


    this.onConnectionState = ({detail: {state}}) => {
      if (state === "connected" || state === "reconnected") this.replay()
    }

    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("submit", this.onSubmit, true)
    this.bindSubmitButton()
    this.el.addEventListener("keydown", this.onKeydown)
    window.addEventListener("chat:connection-state", this.onConnectionState)
    this.replay()
  },

  destroyed() {
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("submit", this.onSubmit, true)
    this.submitButton?.removeEventListener("click", this.onSubmit)
    this.el.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("chat:connection-state", this.onConnectionState)
  },

  updated() {
    this.input = this.el.querySelector('[name="text"]')
    this.bindSubmitButton()
  },

  messages() {
    try {
      const messages = JSON.parse(window.localStorage.getItem(this.storageKey) || "[]")
      return Array.isArray(messages) ? messages : []
    } catch (error) {
      console.warn("Unable to read pending messages from local storage", error)
      return []
    }
  },

  store(messages) {
    try {
      window.localStorage.setItem(this.storageKey, JSON.stringify(messages))
    } catch (_error) {
      // Storage failures must not interrupt chat rendering or reconnect.
    }
  },

  bindSubmitButton() {
    const submitButton = this.el.querySelector('button[type="submit"]')
    if (submitButton === this.submitButton) return

    this.submitButton?.removeEventListener("click", this.onSubmit)
    this.submitButton = submitButton
    this.submitButton?.addEventListener("click", this.onSubmit)
  },

  generateClientId() {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID()

    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
      const random = Math.floor(Math.random() * 16)
      const value = character === "x" ? random : (random & 0x3) | 0x8
      return value.toString(16)
    })
  },

  replay() {
    const messages = this.messages()
    if (messages.length > 0) this.pushEvent("restore_pending_messages", {messages})
  },

  options() {
    return Array.from(this.el.querySelectorAll('[role="option"]'))
  },

  moveActive(delta) {
    const options = this.options()
    const nextIndex = this.activeIndex + delta
    this.activeIndex = nextIndex < 0 ? options.length - 1 : nextIndex % options.length

    options.forEach((option, index) => {
      option.setAttribute("aria-selected", String(index === this.activeIndex))
    })

    const activeOption = options[this.activeIndex]
    if (activeOption) {
      this.input?.setAttribute("aria-activedescendant", activeOption.id)
      activeOption.scrollIntoView({block: "nearest"})
    }
  },

  clearActive() {
    this.activeIndex = -1
    this.input?.removeAttribute("aria-activedescendant")
    this.options().forEach((option) => option.setAttribute("aria-selected", "false"))
  },

}

export default MessageOutbox
