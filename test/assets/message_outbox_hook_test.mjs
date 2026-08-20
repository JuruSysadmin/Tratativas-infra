import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {resolve} from "node:path"

const storage = new Map()
globalThis.crypto.randomUUID = () => "00000000-0000-4000-8000-000000000001"
globalThis.window = {
  localStorage: {
    getItem: (key) => storage.get(key) || null,
    setItem: (key, value) => storage.set(key, value),
    removeItem: (key) => storage.delete(key)
  },
  addEventListener() {},
  removeEventListener() {}
}

const listeners = new Map()
const input = {value: "Mensagem de teste"}
const button = {
  disabled: false,
  addEventListener() {},
  removeEventListener() {}
}
const hook = {
  el: {
    dataset: {outboxStorageKey: "chat:pending:room-1"},
    querySelector(selector) {
      if (selector === '[name="text"]') return input
      if (selector === 'button[type="submit"]') return button
      return null
    },
    querySelectorAll() { return [] },
    requestSubmit() { hook.submitted = true },
    addEventListener(event, callback) { listeners.set(event, callback) },
    removeEventListener() {}
  },
  pushEvent(event, payload) {
    hook.pushedEvent = {event, payload}
  }
}

const source = await readFile(resolve("assets/js/hooks/message_outbox.js"), "utf8")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const {default: MessageOutbox} = await import(moduleUrl)

Object.assign(hook, MessageOutbox)
MessageOutbox.mounted.call(hook)
listeners.get("submit")({
  preventDefault() {},
  stopPropagation() {},
  stopImmediatePropagation() {}
})

assert.deepEqual(JSON.parse(storage.get("chat:pending:room-1")), [
  {client_id: "00000000-0000-4000-8000-000000000001", content: "Mensagem de teste"}
])
assert.deepEqual(hook.pushedEvent, {
  event: "send_message",
  payload: {client_id: "00000000-0000-4000-8000-000000000001", text: "Mensagem de teste"}
})

listeners.get("keydown")({
  target: input,
  key: "Enter",
  shiftKey: false,
  isComposing: false,
  preventDefault() {}
})
assert.equal(hook.submitted, true)

console.log("message outbox hook: ok")
