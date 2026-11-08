// Pure helpers for the mihomo panel: parsing the controller API and
// formatting values. No QML types here, so tests can load this file in node.

// Group names the config template defines. The panel drives these.
var GROUP_VPN = "VPN"
var GROUP_AUTO = "Auto"
var GROUP_RU = "RU"

function parseJson(raw) {
  try {
    var value = JSON.parse(String(raw || ""))
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

// GET /configs -> what the panel shows about the core.
function parseConfigs(raw) {
  var d = parseJson(raw)
  if (!d) return { ok: false }
  var tun = d.tun && typeof d.tun === "object" ? d.tun : {}
  return {
    ok: true,
    mode: String(d.mode || "rule").toLowerCase(),
    tunEnabled: tun.enable === true
  }
}

// The last measured delay of a proxy, 0 when unknown or failed.
function lastDelay(proxy) {
  var history = proxy && proxy.history instanceof Array ? proxy.history : []
  if (history.length === 0) return 0
  var delay = Number(history[history.length - 1].delay)
  return isFinite(delay) && delay > 0 ? Math.round(delay) : 0
}

// "🇫🇮 Финляндия 1" -> { flag: "🇫🇮", country: "FI", label: "Финляндия 1" }.
// Names without a leading flag keep their text as the label.
// Works on UTF-16 surrogate pairs directly: Qt's JS engine iterates strings
// by code unit, so Array.from() would split each flag letter in half.
// A regional indicator letter is U+1F1E6..U+1F1FF = 🇦..🇿.
function splitFlag(name) {
  var text = String(name || "")
  var m = text.match(/^\uD83C([\uDDE6-\uDDFF])\uD83C([\uDDE6-\uDDFF])\s*/)
  if (m) {
    var country = String.fromCharCode(m[1].charCodeAt(0) - 0xDDE6 + 65)
      + String.fromCharCode(m[2].charCodeAt(0) - 0xDDE6 + 65)
    return { flag: text.substring(0, 4), country: country, label: text.substring(m[0].length).trim() }
  }
  return { flag: "", country: "", label: text.trim() }
}

// A compact bar label: "FI 1" for "🇫🇮 Финляндия 1", else the first word.
function shortName(name) {
  var parts = splitFlag(name)
  var digits = parts.label.match(/(\d+)\s*$/)
  if (parts.country !== "") return parts.country + (digits ? " " + digits[1] : "")
  var word = parts.label.split(/\s+/)[0] || ""
  return word.length > 8 ? word.substring(0, 8) : word
}

// GET /providers/proxies/<name> -> { name: proxy }. Nodes that come from a
// proxy-provider are listed only there, not in GET /proxies.
function providerIndex(raw) {
  var d = parseJson(raw)
  var out = {}
  var list = d && d.proxies instanceof Array ? d.proxies : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].name !== undefined) out[String(list[i].name)] = list[i]
  }
  return out
}

// GET /proxies (+ the provider listing) -> the groups and nodes the panel
// lists. Nodes are the VPN group's members except the Auto group, in config
// order; details come from the provider, or from /proxies for nodes written
// inline in the config.
function parseProxies(raw, providerRaw) {
  var d = parseJson(raw)
  var proxies = d && d.proxies && typeof d.proxies === "object" ? d.proxies : null
  if (!proxies) return { ok: false }
  var vpn = proxies[GROUP_VPN]
  if (!vpn || !(vpn.all instanceof Array)) return { ok: false, missingGroup: true }
  var auto = proxies[GROUP_AUTO] || null
  var ru = proxies[GROUP_RU] || null
  var fromProvider = providerIndex(providerRaw)

  var nodes = []
  for (var i = 0; i < vpn.all.length; i++) {
    var name = String(vpn.all[i])
    if (name === GROUP_AUTO) continue
    var p = fromProvider[name] || proxies[name] || {}
    var parts = splitFlag(name)
    nodes.push({
      name: name,
      flag: parts.flag,
      label: parts.label,
      type: String(p.type || ""),
      delay: lastDelay(p),
      alive: p.alive !== false
    })
  }

  var selected = String(vpn.now || "")
  var autoNow = auto ? String(auto.now || "") : ""
  return {
    ok: true,
    nodes: nodes,
    hasAuto: vpn.all.indexOf(GROUP_AUTO) !== -1,
    selected: selected,
    autoNow: autoNow,
    // The node traffic really leaves through right now.
    activeNode: selected === GROUP_AUTO ? autoNow : selected,
    autoDelay: auto ? lastDelay(auto) : 0,
    routing: ru && String(ru.now || "") === GROUP_VPN ? "vpn" : "direct",
    hasRoutingGroup: !!ru
  }
}

// GET /group/<name>/delay -> { name: delay } with failures as 0.
function parseDelays(raw) {
  var d = parseJson(raw)
  var out = {}
  if (!d) return out
  for (var k in d) {
    var n = Number(d[k])
    out[k] = isFinite(n) && n > 0 ? Math.round(n) : 0
  }
  return out
}

// Fold fresh delay measurements into the node list without reordering it.
function applyDelays(nodes, delays) {
  var out = []
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    var copy = {}
    for (var k in n) copy[k] = n[k]
    if (delays && Object.prototype.hasOwnProperty.call(delays, n.name)) {
      copy.delay = delays[n.name]
      copy.alive = delays[n.name] > 0
    }
    out.push(copy)
  }
  return out
}

function delayClass(ms) {
  var n = Number(ms)
  if (!isFinite(n) || n <= 0) return "none"
  if (n < 150) return "good"
  if (n < 400) return "ok"
  return "bad"
}

// Bytes per second -> "820 B/s", "1.4 MB/s"; decimal units like most meters.
function formatRate(bytesPerSec) {
  var n = Math.max(0, Number(bytesPerSec) || 0)
  var units = ["B/s", "KB/s", "MB/s", "GB/s"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000
    i++
  }
  var digits = i === 0 || n >= 100 ? 0 : 1
  return n.toFixed(digits) + " " + units[i]
}

function formatBytes(bytes) {
  var n = Math.max(0, Number(bytes) || 0)
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000
    i++
  }
  var digits = i === 0 || n >= 100 ? 0 : 1
  return n.toFixed(digits) + " " + units[i]
}

// Rate from two cumulative byte counters taken dtMs apart. A counter that
// went backwards (core restarted) reads as zero rather than negative.
function rate(prevTotal, nextTotal, dtMs) {
  var dt = Number(dtMs)
  if (!isFinite(dt) || dt <= 0) return 0
  var delta = Number(nextTotal) - Number(prevTotal)
  if (!isFinite(delta) || delta < 0) return 0
  return delta * 1000 / dt
}

// GET /connections -> totals and the open connection count.
function parseConnections(raw) {
  var d = parseJson(raw)
  if (!d) return { ok: false }
  return {
    ok: true,
    downloadTotal: Number(d.downloadTotal) || 0,
    uploadTotal: Number(d.uploadTotal) || 0,
    count: d.connections instanceof Array ? d.connections.length : 0
  }
}

// controller.json -> { url, secret, service }; url defaults to the local
// controller. service names the systemd unit install.sh set up; a dev run
// has none, and the panel then offers no "start" button.
function parseController(raw) {
  var d = parseJson(raw) || {}
  var url = String(d.url || "http://127.0.0.1:9090").replace(/\/+$/, "")
  if (!/^https?:\/\/[^\s]+$/.test(url)) url = "http://127.0.0.1:9090"
  var service = String(d.service || "")
  if (!/^[A-Za-z0-9@._-]+\.service$/.test(service)) service = ""
  return { url: url, secret: String(d.secret || ""), service: service }
}

// The panel's own remembered state: { tun: true|false|null }.
function parsePanelState(raw) {
  var d = parseJson(raw) || {}
  return { tun: d.tun === true ? true : (d.tun === false ? false : null) }
}

function encodeName(name) {
  return encodeURIComponent(String(name || ""))
}
