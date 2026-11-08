import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Talks to mihomo's REST controller. Owns all state the panel shows; the
// panel only binds to it and calls the action functions.
//
// "On" means the TUN device is up: mihomo keeps running as a service, and
// the switch flips tun.enable through the API, so toggling needs no root.
Item {
  id: root

  property var settings: ({})

  // Controller address and secret come from a small JSON file the installer
  // writes ({"url": "...", "secret": "..."}), not from shell.json, so the
  // secret stays out of the bar layout file.
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string controllerFile: String(setting("controllerFile", "")) || (configHome + "/omarchy-mihomo/controller.json")
  property string _controllerRaw: ""
  readonly property var controller: Model.parseController(_controllerRaw)
  readonly property string controllerUrl: controller.url
  readonly property string secret: controller.secret
  readonly property string serviceName: controller.service
  property bool controllerFileFound: false

  // The switch survives reboots and shell restarts: the core boots with TUN
  // off, and the panel re-applies the last choice once it can reach it.
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string stateFile: stateHome + "/omarchy-mihomo/panel.json"
  property var savedTun: null        // true / false / null = never chosen
  property bool _stateLoaded: false
  property bool _restored: false

  readonly property string providerName: String(setting("provider", "subscription"))
  readonly property string testUrl: String(setting("testUrl", "https://www.gstatic.com/generate_204"))
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 5, 2, 600)

  // Connection to the core.
  property bool reachable: false
  property bool unauthorized: false
  property bool checked: false        // false until the first answer, so the UI does not flash "not running"
  property bool missingGroups: false

  // Core state.
  property bool tunEnabled: false
  property string mode: "rule"
  property var nodes: []
  property bool hasAuto: false
  property string selected: ""
  property string autoNow: ""
  property string activeNode: ""
  property int autoDelay: 0
  property string routing: "direct"
  property bool hasRoutingGroup: false

  // Optimistic switch, as Omarchy's Tailscale panel does: -1 follows the
  // core, 0/1 is a toggle still catching up.
  property int _desired: -1
  property int _tunChecks: 0
  readonly property bool active: _desired === -1 ? tunEnabled : _desired === 1
  readonly property bool switching: _desired !== -1

  property string switchingNode: ""
  property bool testing: false
  property bool updating: false
  property bool starting: false

  // Traffic, polled only while someone is looking (the panel binds this).
  property bool trafficWanted: false
  property real downRate: 0
  property real upRate: 0
  property real downloadTotal: 0
  property real uploadTotal: 0
  property int connectionCount: 0
  property double _lastTrafficMs: 0

  property string actionStatus: ""
  property string lastError: ""
  property string _nodesSig: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  // ------------------------------------------------------------- http

  function request(method, path, body, done) {
    var xhr = new XMLHttpRequest()
    var finished = false
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || finished) return
      finished = true
      if (done) done(xhr.status, xhr.responseText)
    }
    xhr.open(method, controllerUrl + path)
    if (secret !== "") xhr.setRequestHeader("Authorization", "Bearer " + secret)
    if (body !== undefined && body !== null) {
      xhr.setRequestHeader("Content-Type", "application/json")
      xhr.send(JSON.stringify(body))
    } else {
      xhr.send()
    }
  }

  // Status 0 is "nothing listening"; 401 is a wrong secret. Both say the
  // core is out of reach for this panel, so the UI can stop pretending.
  function noteReach(status) {
    checked = true
    if (status === 0) {
      reachable = false
      unauthorized = false
      // The core went away; when it comes back it boots with TUN off.
      _restored = false
      return false
    }
    if (status === 401) {
      reachable = false
      unauthorized = true
      return false
    }
    reachable = true
    unauthorized = false
    return true
  }

  function flash(text) {
    actionStatus = text
    actionStatusTimer.restart()
  }

  function fail(text) {
    lastError = String(text || "")
    actionStatus = ""
  }

  // ---------------------------------------------------------- refresh

  function refresh() {
    request("GET", "/configs", null, function(status, text) {
      if (!root.noteReach(status)) {
        root._desired = -1
        return
      }
      var cfg = Model.parseConfigs(text)
      if (!cfg.ok) return
      root.mode = cfg.mode
      root.tunEnabled = cfg.tunEnabled
      root.restoreSavedState()
      if (root._desired !== -1) {
        if (root.tunEnabled === (root._desired === 1)) {
          root._desired = -1
          root._tunChecks = 0
        } else if (++root._tunChecks >= 3) {
          // The core took the PATCH but the device never followed: usually a
          // user-run core without CAP_NET_ADMIN.
          root._desired = -1
          root._tunChecks = 0
          // Do not remember a state the core could not reach, or a later
          // restore would flip the tunnel on at an unexpected moment.
          root.saveState(root.tunEnabled)
          root.fail("tunFailed")
        }
      }
      root.refreshProxies()
    })
  }

  function refreshProxies() {
    request("GET", "/proxies", null, function(status, text) {
      if (!root.noteReach(status)) return
      // Provider nodes (the subscription) are only listed by the provider.
      root.request("GET", "/providers/proxies/" + Model.encodeName(root.providerName), null, function(pStatus, pText) {
        root.applyProxies(text, pStatus === 200 ? pText : "")
      })
    })
  }

  function applyProxies(text, providerText) {
    var parsed = Model.parseProxies(text, providerText)
    missingGroups = parsed.missingGroup === true
    if (!parsed.ok) return
    publishNodes(parsed.nodes)
    hasAuto = parsed.hasAuto
    if (switchingNode === "") selected = parsed.selected
    autoNow = parsed.autoNow
    activeNode = parsed.activeNode
    // Auto is a group; its own history stays empty when tests run per node,
    // so show the delay of the node it picked.
    autoDelay = parsed.autoDelay > 0 ? parsed.autoDelay : nodeDelay(parsed.nodes, parsed.autoNow)
    routing = parsed.routing
    hasRoutingGroup = parsed.hasRoutingGroup
  }

  function nodeDelay(list, name) {
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i].delay
    return 0
  }

  // Only reassign the array when it changed, so open rows do not rebuild
  // (and lose hover) on every poll.
  function publishNodes(next) {
    var sig = JSON.stringify(next)
    if (sig === _nodesSig) return
    _nodesSig = sig
    nodes = next
  }

  function refreshTraffic() {
    request("GET", "/connections", null, function(status, text) {
      if (!root.noteReach(status)) return
      var c = Model.parseConnections(text)
      if (!c.ok) return
      var now = Date.now()
      if (root._lastTrafficMs > 0) {
        var dt = now - root._lastTrafficMs
        root.downRate = Model.rate(root.downloadTotal, c.downloadTotal, dt)
        root.upRate = Model.rate(root.uploadTotal, c.uploadTotal, dt)
      }
      root._lastTrafficMs = now
      root.downloadTotal = c.downloadTotal
      root.uploadTotal = c.uploadTotal
      root.connectionCount = c.count
    })
  }

  // ---------------------------------------------------------- actions

  // Once per core lifetime as seen by this panel: put the switch back where
  // the user left it. A core that restarts (reboot, service restart) comes
  // back with TUN off, so this runs again after the core was unreachable.
  function restoreSavedState() {
    if (_restored || !_stateLoaded) return
    _restored = true
    if (savedTun === null || savedTun === tunEnabled || _desired !== -1) return
    setTun(savedTun, false)
  }

  function saveState(on) {
    savedTun = on
    stateView.setText(JSON.stringify({ tun: on }) + "\n")
  }

  // remember: false for the automatic restore, true (default) for the user.
  function setTun(on, remember) {
    if (!reachable) return
    if (remember !== false) saveState(on)
    _desired = on ? 1 : 0
    _tunChecks = 0
    lastError = ""
    request("PATCH", "/configs", { tun: { enable: on } }, function(status, text) {
      if (!root.noteReach(status)) return
      if (status >= 300) {
        root._desired = -1
        root.fail(Model.parseJson(text) && Model.parseJson(text).message || ("HTTP " + status))
        return
      }
      tunCheckTimer.restart()
    })
  }

  function toggle() {
    if (!reachable) {
      startService()
      return
    }
    setTun(!active)
  }

  function selectNode(name) {
    var target = String(name || "")
    if (!reachable || target === "" || target === selected || switchingNode !== "") return
    switchingNode = target
    var previous = selected
    selected = target
    request("PUT", "/proxies/" + Model.encodeName(Model.GROUP_VPN), { name: target }, function(status, text) {
      root.switchingNode = ""
      if (!root.noteReach(status)) return
      if (status >= 300) {
        root.selected = previous
        root.fail(Model.parseJson(text) && Model.parseJson(text).message || ("HTTP " + status))
        return
      }
      root.lastError = ""
      root.refreshProxies()
    })
  }

  function setRouting(value) {
    if (!reachable || !hasRoutingGroup) return
    var target = value === "vpn" ? Model.GROUP_VPN : "DIRECT"
    var previous = routing
    routing = value === "vpn" ? "vpn" : "direct"
    request("PUT", "/proxies/" + Model.encodeName(Model.GROUP_RU), { name: target }, function(status, text) {
      if (!root.noteReach(status)) return
      if (status >= 300) {
        root.routing = previous
        root.fail(Model.parseJson(text) && Model.parseJson(text).message || ("HTTP " + status))
        return
      }
      root.lastError = ""
      // Existing connections keep their old route; drop them so the new
      // choice applies at once instead of on the next connection.
      root.request("DELETE", "/connections", null, null)
    })
  }

  function testDelays() {
    if (!reachable || testing) return
    testing = true
    var group = hasAuto ? Model.GROUP_AUTO : Model.GROUP_VPN
    var path = "/group/" + Model.encodeName(group) + "/delay?url=" + encodeURIComponent(testUrl) + "&timeout=5000"
    request("GET", path, null, function(status, text) {
      root.testing = false
      if (!root.noteReach(status)) return
      if (status < 300) {
        root.publishNodes(Model.applyDelays(root.nodes, Model.parseDelays(text)))
        root.lastError = ""
      }
      // A group where every node failed answers 503/504 with no body; the
      // refresh below still brings back each node's failed history.
      root.refreshProxies()
    })
  }

  function updateSubscription() {
    if (!reachable || updating) return
    updating = true
    request("PUT", "/providers/proxies/" + Model.encodeName(providerName), null, function(status, text) {
      root.updating = false
      if (!root.noteReach(status)) return
      if (status >= 300) {
        root.fail(Model.parseJson(text) && Model.parseJson(text).message || ("HTTP " + status))
        return
      }
      root.lastError = ""
      root.flash("updated")
      root.refreshProxies()
    })
  }

  function openDashboard() {
    var url = controllerUrl + "/ui/"
    Quickshell.execDetached(["bash", "-c",
      "command -v omarchy-launch-browser >/dev/null && exec omarchy-launch-browser \"$1\" || exec xdg-open \"$1\"",
      "omarchy-mihomo", url])
  }

  // polkit asks through the shell's own agent when systemd needs it.
  // Only for a core install.sh set up as a service; a dev run has none.
  function startService() {
    if (starting || serviceName === "") return
    starting = true
    startProcess.command = ["systemctl", "start", serviceName]
    startProcess.running = true
  }

  // ----------------------------------------------------------- timers

  FileView {
    id: controllerView
    path: root.controllerFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root._controllerRaw = text()
      root.controllerFileFound = true
      root.refresh()
    }
    onLoadFailed: {
      root._controllerRaw = ""
      root.controllerFileFound = false
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.trafficWanted && root.reachable
    triggeredOnStart: true
    onTriggered: root.refreshTraffic()
    onRunningChanged: if (!running) { root._lastTrafficMs = 0; root.downRate = 0; root.upRate = 0 }
  }

  Timer {
    id: tunCheckTimer
    interval: 700
    repeat: false
    onTriggered: {
      root.refresh()
      if (root._desired !== -1) tunCheckTimer.restart()
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: startProcess
    command: []
    onExited: function(exitCode) {
      root.starting = false
      if (exitCode !== 0) {
        root.fail("systemctl start " + root.serviceName + ": exit " + exitCode)
        return
      }
      // The controller needs a moment after systemd reports the start.
      startupPoll.ticks = 0
      startupPoll.start()
    }
  }

  Timer {
    id: startupPoll
    property int ticks: 0
    interval: 500
    repeat: true
    onTriggered: {
      root.refresh()
      if (root.reachable || ++ticks >= 20) stop()
    }
  }

  FileView {
    id: stateView
    path: root.stateFile
    printErrors: false
    atomicWrites: true
    onLoaded: {
      root.savedTun = Model.parsePanelState(text()).tun
      root._stateLoaded = true
      root.restoreSavedState()
    }
    onLoadFailed: {
      root.savedTun = null
      root._stateLoaded = true
    }
  }
}
