import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {resolve} from "node:path"

const listeners = new Map()
const storage = new Map()

globalThis.window = {
  addEventListener(event, callback) {
    listeners.set(event, callback)
  },
  removeEventListener(event) {
    listeners.delete(event)
  },
  localStorage: {
    getItem(key) {
      return storage.get(key) || null
    },
    setItem(key, value) {
      storage.set(key, value)
    },
    removeItem(key) {
      storage.delete(key)
    }
  }
}

const hookPath = resolve("assets/js/hooks/pending_messages.js")
const source = await readFile(hookPath, "utf8")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const {default: PendingMessages} = await import(moduleUrl)

const hook = {
  el: {
    dataset: {pendingStorageKey: "chat:pending:room-1"},
    querySelectorAll(selector) {
      assert.equal(selector, "[data-pending-message]")

      return [
        {
          dataset: {pendingClientId: "client-1"},
          querySelector(messageSelector) {
            assert.equal(messageSelector, ".message-content")
            return {textContent: "Message during reconnect"}
          }
        }
      ]
    }
  },
  pushEvent() {
    assert.fail("No message must be restored before the reconnect")
  },
  ...PendingMessages
}

PendingMessages.mounted.call(hook)

assert.equal(typeof listeners.get("chat:connection-state"), "function")
listeners.get("chat:connection-state")({detail: {state: "reconnecting"}})

assert.deepEqual(JSON.parse(storage.get("chat:pending:room-1")), [
 {client_id: "client-1", content: "Message during reconnect"}
 ])

PendingMessages.destroyed.call(hook)
console.log("pending messages hook: ok")
