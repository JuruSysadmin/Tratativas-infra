const AUDIO_URL = "/assets/notification.wav"
const MINIMUM_INTERVAL_MS = 1_200
const VOLUME = 0.25

let audio = null
let lastPlayedAt = 0

function notificationAudio() {
  if (!audio) {
    audio = new Audio(AUDIO_URL)
    audio.preload = "auto"
    audio.volume = VOLUME
  }

  return audio
}

function unlockAudio() {
  const sound = notificationAudio()
  sound.muted = true

  sound.play().then(() => {
    sound.pause()
    sound.currentTime = 0
    sound.muted = false
  }).catch(() => {
    sound.muted = false
  })
}

function playNotification() {
  const now = Date.now()
  if (now - lastPlayedAt < MINIMUM_INTERVAL_MS) return

  lastPlayedAt = now

  const sound = notificationAudio()
  sound.currentTime = 0
  sound.play().catch(() => {})
}

export default {
  mounted() {
    this.unlockAudio = () => unlockAudio()
    window.addEventListener("pointerdown", this.unlockAudio, {once: true})
    this.handleEvent("play_notification_sound", playNotification)
  },

  destroyed() {
    window.removeEventListener("pointerdown", this.unlockAudio)
  }
}
