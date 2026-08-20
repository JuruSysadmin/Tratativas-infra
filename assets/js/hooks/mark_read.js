const MarkRead = {
  mounted() {
    this.deliveredMessageIds = new Set()
    this.markedMessageIds = new Set()
    this.wasAtBottom = true
    this.previousHeight = 0
    this.lastChildId = null

    const root = this.el.closest(".messages-container") || this.el

    this.observer = new IntersectionObserver(
      (entries) => {
        const visibleIds = entries
          .filter((entry) => entry.isIntersecting)
          .map((entry) => entry.target.dataset.messageId)
          .filter((id) => id && !this.markedMessageIds.has(id))

        this.markAsRead(visibleIds)
      },
      {
        root,
        threshold: 0.5
      }
    )

    const messages = this.el.querySelectorAll("[data-mark-readable]")
    messages.forEach((el) => {
      this.observer.observe(el)
    })

    this.markDelivered(Array.from(messages).map((message) => message.dataset.messageId))

    const rootRect = root.getBoundingClientRect()
    const initiallyVisibleIds = Array.from(messages)
      .filter((message) => {
        const rect = message.getBoundingClientRect()
        const visibleHeight = Math.min(rect.bottom, rootRect.bottom) - Math.max(rect.top, rootRect.top)
        return rect.height > 0 && visibleHeight / rect.height >= 0.5
      })
      .map((message) => message.dataset.messageId)

    this.markAsRead(initiallyVisibleIds)
    this.lastChildId = this.getLastMessageId()
    this.scrollToBottom()
  },

  markDelivered(messageIds) {
    const undeliveredIds = messageIds.filter((id) => id && !this.deliveredMessageIds.has(id))
    if (undeliveredIds.length > 0) {
      undeliveredIds.forEach((id) => this.deliveredMessageIds.add(id))
      this.pushEvent("mark_delivered", {message_ids: undeliveredIds})
    }
  },

  markAsRead(messageIds) {
    const unreadIds = messageIds.filter((id) => id && !this.markedMessageIds.has(id))
    if (unreadIds.length > 0) {
      unreadIds.forEach((id) => this.markedMessageIds.add(id))
      this.pushEvent("mark_read", { message_ids: unreadIds })
    }
  },

  beforeUpdate() {
    this.previousHeight = this.el.scrollHeight
    this.wasAtBottom =
      this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 24
    this.previousLastChildId = this.lastChildId
  },

  updated() {
    const messages = this.el.querySelectorAll("[data-mark-readable]")
    messages.forEach((el) => {
      this.observer.observe(el)
    })
    this.markDelivered(Array.from(messages).map((message) => message.dataset.messageId))

    const newLastChildId = this.getLastMessageId()
    const appended = newLastChildId !== this.previousLastChildId
    this.lastChildId = newLastChildId

    if (appended) {
      this.scrollToBottom()
    } else if (this.wasAtBottom) {
      this.scrollToBottom()
    } else {
      const heightDelta = this.el.scrollHeight - this.previousHeight
      if (heightDelta > 0) {
        this.el.scrollTop += heightDelta
      }
    }
  },

  getLastMessageId() {
    const last = this.el.querySelector("[data-message-id]:last-child")
    return last ? last.dataset.messageId : null
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  },

  destroyed() {
    this.observer.disconnect()
  }
}

export default MarkRead
