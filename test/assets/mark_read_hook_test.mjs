import assert from "node:assert/strict"
import {readFile} from "node:fs/promises"
import {resolve} from "node:path"

class FakeIntersectionObserver {
  constructor(callback) {
    this.callback = callback
  }

  disconnect() {}
  observe() {}
}

const message = {
  dataset: {messageId: "foreign-message"},
  getBoundingClientRect() {
    return {top: 0, bottom: 100, height: 100}
  }
}

const root = {
  getBoundingClientRect() {
    return {top: 0, bottom: 200}
  }
}

const element = {
  clientHeight: 200,
  scrollHeight: 200,
  scrollTop: 0,
  closest() {
    return root
  },
  querySelectorAll(selector) {
    return selector === "[data-mark-readable]" ? [message] : []
  },
  querySelector() {
    return null
  }
}

globalThis.IntersectionObserver = FakeIntersectionObserver

const source = await readFile(resolve("assets/js/hooks/mark_read.js"), "utf8")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const {default: MarkRead} = await import(moduleUrl)
const events = []
const hook = {
  el: element,
  pushEvent(event, payload) {
    events.push({event, payload})
  }
}

Object.assign(hook, MarkRead)
hook.mounted()

assert.deepEqual(events.find(({event}) => event === "mark_delivered"), {
  event: "mark_delivered",
  payload: {message_ids: ["foreign-message"]}
})

console.log("mark read hook: ok")
