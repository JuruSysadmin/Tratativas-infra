import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {resolve} from "node:path"

const listeners = new Map()
globalThis.window = {
  chatConnectionState: "connected",
  addEventListener(event, callback) {
    listeners.set(event, callback)
  },
  removeEventListener(event) {
    listeners.delete(event)
  }
}

const hookPath = resolve("assets/js/hooks/connection_status.js")
const source = await readFile(hookPath, "utf8")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const {default: ConnectionStatus} = await import(moduleUrl)

const hook = {
  el: {
    dataset: {connectionState: "connected"},
    hidden: true,
    textContent: ""
  },
  ...ConnectionStatus
}

ConnectionStatus.mounted.call(hook)
assert.equal(hook.el.hidden, true)

listeners.get("chat:connection-state")({detail: {state: "reconnecting"}})
assert.equal(hook.el.dataset.connectionState, "reconnecting")
assert.equal(hook.el.textContent, "Reconectando ao chat…")
assert.equal(hook.el.hidden, false)

listeners.get("chat:connection-state")({detail: {state: "disconnected"}})
assert.equal(hook.el.dataset.connectionState, "disconnected")
assert.equal(hook.el.textContent, "Conexão perdida. Tentando reconectar…")

listeners.get("chat:connection-state")({detail: {state: "reconnected"}})
assert.equal(hook.el.dataset.connectionState, "reconnected")
assert.equal(hook.el.textContent, "Conexão restabelecida.")
assert.equal(hook.el.hidden, false)

await new Promise((resolve) => setTimeout(resolve, 2600))
assert.equal(hook.el.hidden, true)

ConnectionStatus.destroyed.call(hook)
console.log("connection status hook: ok")
