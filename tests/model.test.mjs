// node --test tests/
// Loads the plugin's QML-side JS files (plain scripts, no modules) into a
// sandbox and checks the parsing and formatting the panel relies on.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

function load(file) {
  const ctx = vm.createContext({})
  vm.runInContext(readFileSync(new URL(`../${file}`, import.meta.url), "utf8"), ctx)
  return ctx
}

const M = load("Model.js")
const S = load("Strings.js")

// Trimmed answers from mihomo 1.19.33 with our template. As in the real
// API, subscription nodes appear in GET /proxies only as group members;
// their details are listed by GET /providers/proxies/subscription.
const proxies = {
  proxies: {
    VPN: { type: "Selector", now: "Auto", all: ["Auto", "🇫🇮 Финляндия 1", "🇱🇻 Латвия 2"] },
    Auto: { type: "URLTest", now: "🇱🇻 Латвия 2", all: ["🇫🇮 Финляндия 1", "🇱🇻 Латвия 2"], history: [{ delay: 99 }] },
    RU: { type: "Selector", now: "DIRECT", all: ["DIRECT", "VPN"] },
    DIRECT: { type: "Direct" },
  },
}
const provider = {
  name: "subscription",
  proxies: [
    { name: "🇫🇮 Финляндия 1", type: "Vless", alive: true, history: [{ delay: 140 }, { delay: 71 }] },
    { name: "🇱🇻 Латвия 2", type: "Vless", alive: false, history: [{ delay: 0 }] },
  ],
}
const P = (px = proxies, pv = provider) => M.parseProxies(JSON.stringify(px), pv ? JSON.stringify(pv) : "")

test("parseProxies takes node details from the provider", () => {
  const p = P()
  assert.equal(p.nodes[0].delay, 71)
  assert.equal(p.nodes[0].type, "Vless")
  const bare = P(proxies, null)
  assert.equal(bare.nodes.length, 2, "nodes still listed without the provider")
  assert.equal(bare.nodes[0].delay, 0)
})

test("parseProxies falls back to /proxies for inline nodes", () => {
  const inline = structuredClone(proxies)
  inline.proxies["🇫🇮 Финляндия 1"] = { type: "Trojan", history: [{ delay: 42 }] }
  assert.equal(P(inline, null).nodes[0].delay, 42)
})

test("parseProxies lists nodes in group order without Auto", () => {
  const p = P()
  assert.equal(p.ok, true)
  assert.deepEqual(Array.from(p.nodes, (n) => n.name), ["🇫🇮 Финляндия 1", "🇱🇻 Латвия 2"])
  assert.equal(p.nodes[0].delay, 71, "last history entry wins")
  assert.equal(p.nodes[0].flag, "🇫🇮")
  assert.equal(p.nodes[0].label, "Финляндия 1")
  assert.equal(p.nodes[1].delay, 0)
  assert.equal(p.nodes[1].alive, false)
})

test("parseProxies resolves the node Auto is using", () => {
  const p = P()
  assert.equal(p.selected, "Auto")
  assert.equal(p.autoNow, "🇱🇻 Латвия 2")
  assert.equal(p.activeNode, "🇱🇻 Латвия 2")
  assert.equal(p.autoDelay, 99)
  assert.equal(p.hasAuto, true)
})

test("parseProxies reads routing from the RU group", () => {
  assert.equal(P().routing, "direct")
  const vpn = structuredClone(proxies)
  vpn.proxies.RU.now = "VPN"
  assert.equal(P(vpn).routing, "vpn")
  delete vpn.proxies.RU
  assert.equal(P(vpn).hasRoutingGroup, false)
})

test("parseProxies flags a config without the VPN group", () => {
  const p = M.parseProxies(JSON.stringify({ proxies: { GLOBAL: { all: [] } } }))
  assert.equal(p.ok, false)
  assert.equal(p.missingGroup, true)
  assert.equal(M.parseProxies("not json").ok, false)
})

test("parseConfigs reads mode and tun state", () => {
  assert.deepEqual(
    JSON.parse(JSON.stringify(M.parseConfigs('{"mode":"Rule","tun":{"enable":true}}'))),
    { ok: true, mode: "rule", tunEnabled: true })
  assert.equal(M.parseConfigs('{"mode":"rule"}').tunEnabled, false)
  assert.equal(M.parseConfigs("").ok, false)
})

test("splitFlag and shortName", () => {
  assert.equal(M.splitFlag("🇫🇮 Финляндия 1").country, "FI")
  assert.equal(M.shortName("🇫🇮 Финляндия 1"), "FI 1")
  assert.equal(M.shortName("🇱🇻 Латвия"), "LV")
  assert.equal(M.shortName("Amsterdam-03"), "Amsterda")
  assert.equal(M.shortName(""), "")
  assert.equal(M.splitFlag("plain").label, "plain")
})

test("delays fold into nodes and classify", () => {
  const nodes = P().nodes
  const next = M.applyDelays(nodes, M.parseDelays('{"🇫🇮 Финляндия 1": 64, "🇱🇻 Латвия 2": 0}'))
  assert.equal(next[0].delay, 64)
  assert.equal(next[1].alive, false)
  assert.equal(nodes[0].delay, 71, "input is not mutated")
  assert.equal(M.delayClass(64), "good")
  assert.equal(M.delayClass(250), "ok")
  assert.equal(M.delayClass(900), "bad")
  assert.equal(M.delayClass(0), "none")
})

test("rates and sizes", () => {
  assert.equal(M.formatRate(820), "820 B/s")
  assert.equal(M.formatRate(1400000), "1.4 MB/s")
  assert.equal(M.formatRate(-5), "0 B/s")
  assert.equal(M.formatBytes(250_000_000), "250 MB")
  assert.equal(M.rate(1000, 3000, 1000), 2000)
  assert.equal(M.rate(5000, 100, 1000), 0, "counter reset reads as zero")
  assert.equal(M.rate(0, 100, 0), 0)
})

test("connections and controller file", () => {
  const c = M.parseConnections('{"downloadTotal":10,"uploadTotal":2,"connections":[{},{}]}')
  assert.equal(c.count, 2)
  assert.equal(c.downloadTotal, 10)
  assert.equal(M.parseController("").url, "http://127.0.0.1:9090")
  assert.equal(M.parseController('{"url":"http://127.0.0.1:9191/","secret":"s"}').url, "http://127.0.0.1:9191")
  assert.equal(M.parseController('{"url":"javascript:alert(1)"}').url, "http://127.0.0.1:9090")
  assert.equal(M.encodeName("🇫🇮 Финляндия 1"), encodeURIComponent("🇫🇮 Финляндия 1"))
})

test("controller service and panel state", () => {
  assert.equal(M.parseController('{"service":"mihomo.service"}').service, "mihomo.service")
  assert.equal(M.parseController('{"service":"x; rm -rf /"}').service, "", "only plain unit names")
  assert.equal(M.parseController("").service, "")
  assert.equal(M.parsePanelState('{"tun":true}').tun, true)
  assert.equal(M.parsePanelState('{"tun":false}').tun, false)
  assert.equal(M.parsePanelState("").tun, null)
  assert.equal(M.parsePanelState('{"tun":"yes"}').tun, null)
})

test("strings: language, fallback and holes", () => {
  assert.equal(S.t("ru", "on"), "Подключено")
  assert.equal(S.t("en", "on"), "Connected")
  assert.equal(S.t("de", "on"), "Connected", "unknown language falls back to English")
  assert.equal(S.t("ru", "ms", 64), "64 мс")
  assert.equal(S.t("ru", "Some raw error"), "Some raw error", "unknown key shows as is")
  const en = Object.keys(vm.runInContext("catalogs.en", S)).sort()
  const ru = Object.keys(vm.runInContext("catalogs.ru", S)).sort()
  assert.deepEqual(ru, en, "ru and en carry the same keys")
})
