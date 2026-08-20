import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {resolve} from "node:path"

class FakeAudio {
  static instances = []

  constructor(url) {
    this.url = url
    this.currentTime = 5
    this.muted = false
    this.pauseCalls = 0
    this.playCalls = 0
    FakeAudio.instances.push(this)
  }

  pause() {
    this.pauseCalls += 1
  }

  play() {
    this.playCalls += 1
    return Promise.resolve()
  }
}

const listeners = new Map()
globalThis.Audio = FakeAudio
globalThis.window = {
  addEventListener(event, callback) {
    listeners.set(event, callback)
  },
  removeEventListener(event) {
    listeners.delete(event)
  }
}

const hookPath = resolve("assets/js/hooks/notification_sound.js")
const source = await readFile(hookPath, "utf8")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const {default: NotificationSound} = await import(moduleUrl)
const handlers = new Map()
const hook = {
  handleEvent(event, callback) {
    handlers.set(event, callback)
  }
}

NotificationSound.mounted.call(hook)
handlers.get("play_notification_sound")()

const [sound] = FakeAudio.instances
assert.equal(sound.url, "/assets/notification.wav")
assert.equal(sound.currentTime, 0)
assert.equal(sound.playCalls, 1)

handlers.get("play_notification_sound")()
assert.equal(sound.playCalls, 1)

console.log("notification sound hook: ok")
