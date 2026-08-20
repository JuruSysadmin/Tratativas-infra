const MentionCombobox = {
  mounted() {
    this.activeIndex = -1

    this.onKeydown = (event) => {
      if (event.target !== this.input()) return

      const options = this.options()

      switch (event.key) {
        case "ArrowDown":
          if (options.length === 0) return
          event.preventDefault()
          this.moveActive(1)
          break

        case "ArrowUp":
          if (options.length === 0) return
          event.preventDefault()
          this.moveActive(-1)
          break

        case "Enter":
          if (this.activeIndex < 0 || !options[this.activeIndex]) return
          event.preventDefault()
          options[this.activeIndex].click()
          break

        case "Escape":
          if (options.length === 0) return
          event.preventDefault()
          this.clearActive()
          this.pushEvent("dismiss_mentions", {})
          break
      }
    }

    this.onPointerDown = (event) => {
      if (event.target.closest('[role="option"]')) {
        event.preventDefault()
        event.stopPropagation()
      }
    }

    this.el.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("pointerdown", this.onPointerDown)
  },

  updated() {
    const options = this.options()

    if (this.activeIndex >= options.length) {
      this.clearActive()
    } else if (this.activeIndex >= 0) {
      this.applyActive()
    }
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.onKeydown)
    this.el.removeEventListener("pointerdown", this.onPointerDown)
  },

  input() {
    return this.el.querySelector('[role="combobox"]')
  },

  options() {
    return Array.from(this.el.querySelectorAll('[role="option"]'))
  },

  moveActive(delta) {
    const options = this.options()
    const nextIndex = this.activeIndex + delta

    if (nextIndex < 0) {
      this.activeIndex = options.length - 1
    } else {
      this.activeIndex = nextIndex % options.length
    }

    this.applyActive()
  },

  applyActive() {
    const input = this.input()
    const options = this.options()
    const activeOption = options[this.activeIndex]

    options.forEach((option, index) => {
      option.setAttribute("aria-selected", String(index === this.activeIndex))
    })

    if (input && activeOption) {
      input.setAttribute("aria-activedescendant", activeOption.id)
      activeOption.scrollIntoView({block: "nearest"})
    }
  },

  clearActive() {
    this.activeIndex = -1

    const input = this.input()
    if (input) input.removeAttribute("aria-activedescendant")

    this.options().forEach((option) => {
      option.setAttribute("aria-selected", "false")
    })
  }
}

export default MentionCombobox
