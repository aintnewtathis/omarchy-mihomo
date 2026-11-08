import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Strings.js" as S

Panel {
  id: root
  moduleName: "aintnewtathis.mihomo"
  ipcTarget: "aintnewtathis.mihomo"
  manageIpc: false

  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null

  // Glyphs (Material Design Icons in the Nerd Font).
  readonly property string glyphOn: "\u{F0565}"        // shield-check
  readonly property string glyphOff: "\u{F099E}"       // shield-off
  readonly property string glyphDown: "\u{F099D}"      // shield-off-outline
  readonly property string glyphAuto: "\u{F0241}"      // flash
  readonly property string glyphTest: "\u{F04C5}"      // speedometer
  readonly property string glyphUpdate: "\u{F0450}"    // refresh
  readonly property string glyphStart: "\u{F040A}"     // play

  // "auto" follows the shell language; "ru"/"en" pin it.
  readonly property string lang: {
    var pinned = String(setting("language", "auto"))
    return pinned === "auto" || pinned === "" ? Commons.I18n.language : pinned
  }
  function t(key) {
    var args = [root.lang, key]
    for (var i = 1; i < arguments.length; i++) args.push(arguments[i])
    return S.t.apply(null, args)
  }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"

  readonly property bool up: vpn.reachable
  readonly property bool connected: up && vpn.active && !vpn.switching
  readonly property bool showLabel: setting("showLabel", false) === true

  readonly property string barGlyph: !up ? glyphDown : (vpn.active ? glyphOn : glyphOff)
  readonly property color barIconColor: up && vpn.active ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property string stateText: {
    if (!vpn.checked) return ""
    if (vpn.unauthorized) return t("unauthorized")
    if (!up) return t("notRunning")
    if (vpn.switching) return vpn._desired === 1 ? t("turningOn") : t("turningOff")
    return vpn.active ? t("on") : t("off")
  }

  // "Connected · Финляндия 2"; latency lives in the server list.
  readonly property string heroMeta: connected && vpn.activeNode !== ""
    ? stateText + " · " + Model.splitFlag(vpn.activeNode).label
    : stateText

  readonly property string barTooltip: connected && vpn.activeNode !== ""
    ? t("title") + " · " + vpn.activeNode
    : t("title") + " · " + stateText

  // Rows the cursor walks in the server list: Auto first, then the nodes.
  readonly property var rows: {
    var out = []
    if (vpn.hasAuto) out.push({ name: Model.GROUP_AUTO, isAuto: true })
    for (var i = 0; i < vpn.nodes.length; i++) out.push(vpn.nodes[i])
    return out
  }

  readonly property var routingOptions: [
    { value: "direct", label: t("routingDirect"), tooltip: t("routingDirectHint") },
    { value: "vpn", label: t("routingVpn"), tooltip: t("routingVpnHint") }
  ]

  // ------------------------------------------------- keyboard cursor
  // Sections, top to bottom: header (switch) -> routing -> rows.
  // Ping and subscription update are on p / u (and the header buttons).
  property string focusSection: "header"
  property int rowIndex: 0
  property int routingIndex: 0
  property bool cursorActive: false

  function nodeByName(name) {
    for (var i = 0; i < vpn.nodes.length; i++) if (vpn.nodes[i].name === name) return vpn.nodes[i]
    return null
  }

  function hasDelays() {
    for (var i = 0; i < vpn.nodes.length; i++) if (vpn.nodes[i].delay > 0) return true
    return false
  }

  function sections() {
    var list = ["header"]
    if (up && vpn.hasRoutingGroup) list.push("routing")
    if (up && rows.length > 0) list.push("rows")
    return list
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    var list = sections()
    var at = list.indexOf(focusSection)
    if (at === -1) { focusSection = list[0]; return }
    if (dx !== 0) {
      if (focusSection === "routing") routingIndex = Math.max(0, Math.min(routingOptions.length - 1, routingIndex + dx))
      return
    }
    if (focusSection === "rows") {
      var next = rowIndex + dy
      if (next >= 0 && next < rows.length) { rowIndex = next; scrollToCursor(); return }
    }
    var target = Math.max(0, Math.min(list.length - 1, at + (dy > 0 ? 1 : -1)))
    if (target === at) return
    focusSection = list[target]
    if (focusSection === "rows") rowIndex = dy > 0 ? 0 : rows.length - 1
    if (focusSection === "routing") routingIndex = vpn.routing === "vpn" ? 1 : 0
    scrollToCursor()
  }

  function activateCursor() {
    if (focusSection === "header") vpn.toggle()
    else if (focusSection === "routing") vpn.setRouting(routingOptions[routingIndex].value)
    else if (focusSection === "rows" && rows[rowIndex]) vpn.selectNode(rows[rowIndex].name)
  }

  function scrollToCursor() {
    if (!panelFlick || !panel.loadedContent) return
    if (focusSection !== "rows") {
      if (focusSection === "header") panelFlick.contentY = 0
      return
    }
    var col = panel.loadedContent.rowColumn
    var item = col && rowIndex < col.children.length ? col.children[rowIndex] : null
    if (!item) return
    Qt.callLater(function() {
      var margin = Style.space(6)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
    vpn.refresh()
    // The core health-checks lazily, so a fresh start has no latencies yet;
    // measure once instead of showing a column of dashes.
    if (vpn.reachable && !hasDelays()) vpn.testDelays()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  Service {
    id: vpn
    settings: root.settings
    trafficWanted: root.opened && root.connected
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function on(): string { vpn.setTun(true); return "ok" }
    function off(): string { vpn.setTun(false); return "ok" }
    function switchVpn(): string { vpn.toggle(); return "ok" }
    function refresh(): string { vpn.refresh(); return "ok" }
    function status(): string { return root.stateText + (vpn.activeNode !== "" ? " " + vpn.activeNode : "") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    foreground: root.barIconColor
    labelText: root.showLabel && root.connected ? Model.shortName(vpn.activeNode) : ""
    tooltipText: root.opened ? "" : root.barTooltip
    onPressed: function(code) {
      if (code === Qt.RightButton) vpn.toggle()
      else if (code === Qt.MiddleButton) vpn.testDelays()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      property alias rowColumn: rowColumn
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var k = String(text).toLowerCase()
        if (k === "t") vpn.toggle()
        else if (k === "p") vpn.testDelays()
        else if (k === "u") vpn.updateSubscription()
        else if (k === "d") vpn.openDashboard()
        else if (k === "a" && vpn.hasAuto) vpn.selectNode(Model.GROUP_AUTO)
        else if (k === "m") vpn.setRouting(vpn.routing === "vpn" ? "direct" : "vpn")
        else if (k === "r") vpn.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ------------------------------------------------ header
          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"

            PanelHero {
              id: hero
              width: parent.width
              title: root.t("title")
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.up && vpn.active ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  textFormat: Text.PlainText
                  text: root.barGlyph
                  color: root.up && vpn.active ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: root.up
                  checked: vpn.active
                  busy: vpn.switching
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "header" } }
                  onToggled: vpn.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: vpn.active ? root.t("turnOff") : root.t("turnOn")
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          // Live speed, only while traffic actually goes through the VPN.
          Row {
            visible: root.connected
            width: parent.width

            Repeater {
              model: [
                { arrow: "↓", rate: vpn.downRate },
                { arrow: "↑", rate: vpn.upRate }
              ]
              Text {
                required property var modelData
                width: parent.width / 2
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.arrow + "  " + Model.formatRate(modelData.rate)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          // Status / error line.
          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? root.t(vpn.actionStatus) : (vpn.lastError !== "" ? root.t(vpn.lastError) : "")
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          // ---------------------------------- core not reachable
          Column {
            visible: vpn.checked && !root.up
            width: parent.width
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              text: !vpn.controllerFileFound ? root.t("noControllerHelp", vpn.controllerFile)
                : (vpn.unauthorized ? root.t("unauthorized")
                : (vpn.serviceName !== "" ? root.t("notRunningHelp") : root.t("notRunningDevHelp")))
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              visible: !vpn.unauthorized && vpn.serviceName !== ""
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.t("startService")
              iconText: root.glyphStart
              bordered: true
              hasCursor: root.cursorActive && root.focusSection === "header"
              enabled: !vpn.starting
              opacity: vpn.starting ? 0.5 : 1.0
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: vpn.startService()
            }
          }

          // --------------------------------------------- routing
          PanelSeparator { visible: root.up && vpn.hasRoutingGroup; foreground: root.foreground }

          Column {
            visible: root.up && vpn.hasRoutingGroup
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.t("routing")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Two equal halves rather than ButtonGroup's content-sized chips.
            Row {
              id: routingRow
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: root.routingOptions
                Button {
                  required property var modelData
                  required property int index
                  width: (routingRow.width - routingRow.spacing) / 2
                  text: modelData.label
                  tooltipText: modelData.tooltip
                  selected: vpn.routing === modelData.value
                  bordered: true
                  hasCursor: root.cursorActive && root.focusSection === "routing" && root.routingIndex === index
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: vpn.setRouting(modelData.value)
                  onHovered: function(isHovered) {
                    if (!isHovered) return
                    root.cursorActive = true
                    root.focusSection = "routing"
                    root.routingIndex = index
                  }
                }
              }
            }
          }

          // --------------------------------------------- servers
          PanelSeparator { visible: root.up; foreground: root.foreground }

          Column {
            visible: root.up
            width: parent.width
            spacing: Style.space(8)

            // Section title with its two actions on the trailing edge.
            Item {
              width: parent.width
              implicitHeight: Math.max(serversTitle.implicitHeight, serverActions.implicitHeight)

              PanelSectionHeader {
                id: serversTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("servers")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Row {
                id: serverActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                PanelActionButton {
                  iconText: root.glyphTest
                  tooltipText: vpn.testing ? root.t("testing") : root.t("testDelays")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !vpn.testing
                  opacity: vpn.testing ? 0.4 : 1.0
                  onClicked: vpn.testDelays()
                }
                PanelActionButton {
                  iconText: root.glyphUpdate
                  tooltipText: root.t("updateSubscription")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !vpn.updating
                  opacity: vpn.updating ? 0.4 : 1.0
                  onClicked: vpn.updateSubscription()
                }
              }
            }

            Text {
              visible: root.rows.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: vpn.missingGroups ? root.t("missingGroups") : root.t("noServers")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: rowColumn
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.rows
                NodeRow {
                  required property var modelData
                  required property int index
                  width: rowColumn.width
                  node: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  // ----------------------------------------------------- components

  // One line per server: flag (or the Auto glyph), name, latency. The
  // chosen row carries the selected fill, as Bluetooth's connected rows do.
  component NodeRow: CursorSurface {
    id: nodeRow
    property var node: null
    property int rowIndex: 0
    readonly property bool isAuto: !!(node && node.isAuto)
    readonly property string name: node ? String(node.name) : ""
    readonly property bool isSelected: vpn.selected === name
    readonly property int delay: isAuto ? vpn.autoDelay : (node ? node.delay : 0)
    readonly property string delayKind: Model.delayClass(delay)
    // Auto names the server it picked, dimmed, after its own label.
    readonly property string autoPick: isAuto && vpn.autoNow !== "" ? Model.splitFlag(vpn.autoNow).label : ""

    hasCursor: root.cursorActive && root.focusSection === "rows" && root.rowIndex === rowIndex
    current: isSelected
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: nameText.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "rows"
        root.rowIndex = nodeRow.rowIndex
      }
      onClicked: vpn.selectNode(nodeRow.name)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: nodeRow.isAuto ? root.glyphAuto : (nodeRow.node && nodeRow.node.flag ? nodeRow.node.flag : "\u{F01E7}")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(18)
        horizontalAlignment: Text.AlignHCenter
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        id: nameText
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: nodeRow.isAuto ? root.t("auto") : (nodeRow.node ? nodeRow.node.label : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignVCenter

        Text {
          visible: nodeRow.autoPick !== ""
          x: nameText.implicitWidth + Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: nodeRow.autoPick
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        textFormat: Text.PlainText
        text: nodeRow.delayKind === "none" ? "—" : root.t("ms", nodeRow.delay)
        color: nodeRow.delayKind === "bad" ? root.urgent : (nodeRow.delayKind === "good" ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(56)
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
