const MessageLoading = {
  mounted() {
    this.showLoading = () => {
      this.el.hidden = false
    }

    this.hideLoading = () => {
      this.el.hidden = true
    }

    this.hideLoading()
    window.addEventListener("phx:page-loading-start", this.showLoading)
    window.addEventListener("phx:page-loading-stop", this.hideLoading)
  },

  destroyed() {
    window.removeEventListener("phx:page-loading-start", this.showLoading)
    window.removeEventListener("phx:page-loading-stop", this.hideLoading)
  }
}

export default MessageLoading
