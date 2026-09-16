pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// DimAgent usage in the bar: the credit ledger the plan grants, when it
// resets, the feature allowances that ride along with it, and what this
// machine's sessions have spent.
//
// The widget is a display, never an authority: every number here comes from
// scripts/dim-usage, which runs the `dim` CLI. Reading happens in Usage.qml;
// this file is layout, wording, and key handling.
Panel {
  id: dimPanel

  moduleName: "sunny0826.dim"
  // The widget registers its own IpcHandler below instead of using the base
  // class's, so it can offer a status line beside open/close/toggle.
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent, urgent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool barVertical: bar ? bar.vertical : false
  readonly property string displayMode: Model.normalizeDisplay(setting("barDisplay", "Remaining"))
  readonly property string markMode: Model.normalizeMark(setting("barMark", "Mono"))
  readonly property bool markTinted: Model.markIsTinted(markMode)
  // The mark carries the alarm when it follows the theme (Mono): it turns
  // urgent. In brand colours the percentage beside it does the talking
  // instead, since recolouring the logo would not be the logo any more.
  readonly property bool markAlarming: alarming || (hasData && !ok)
  readonly property color markColor: markAlarming ? urgent : foreground

  readonly property var snapshot: usage.snapshot
  readonly property bool hasData: snapshot !== null
  readonly property bool ok: usage.ok
  readonly property string errorText: usage.error
  readonly property bool alarming: Model.alarming(snapshot)

  // Derived once here rather than re-tested in every row: the panel stays
  // readable and a null snapshot can only be handled in one place.
  readonly property var plan: snapshot ? snapshot.plan : null
  readonly property var subscription: snapshot ? snapshot.subscription : null
  readonly property var credits: snapshot ? snapshot.credits : null
  readonly property var term: snapshot ? snapshot.term : null
  readonly property var features: snapshot ? snapshot.features : null
  readonly property var models: snapshot ? snapshot.models : null
  readonly property var tokens: snapshot ? snapshot.tokens : null
  readonly property string usageError: Model.usageErrorText(snapshot)
  readonly property var featureRows: Model.featureRows(features)
  readonly property var dayRows: Model.dayRows(tokens, nowMs)
  readonly property var tokenModelRows: Model.modelRows(tokens, 3)

  readonly property bool hasCredits: credits !== null && Number(credits.total) > 0
  readonly property bool hasFeatures: featureRows.length > 0
  readonly property bool hasTokens: tokens !== null

  // Countdowns and "updated" read this instead of Date.now() so a panel left
  // open keeps telling the truth.
  property double nowMs: Date.now()

  // The CLI is missing on machines that never installed it: leave the bar
  // rather than occupy a slot with a dead icon.
  visible: usage.installed
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refreshNow() {
    usage.refresh()
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    content.resetScroll()
    usage.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Usage {
    id: usage
    settings: dimPanel.settings
  }

  // A small IPC surface, reached through Quickshell itself:
  //   quickshell ipc -p /usr/share/omarchy/shell call sunny0826.dim status
  //   quickshell ipc -p /usr/share/omarchy/shell call sunny0826.dim toggle
  // `omarchy-shell shell call` only reaches panel/overlay plugins (see
  // callIfLoaded in the shell), so a bar widget is not addressable that way.
  // The base class's own handler is skipped because this needs `status` too.
  IpcHandler {
    target: "sunny0826.dim"

    function open(): void { dimPanel.open() }
    function close(): void { dimPanel.close() }
    function toggle(): void { dimPanel.toggle() }
    function refresh(): void { dimPanel.refreshNow() }

    function status(): string {
      var credits = dimPanel.credits
      var tokens = dimPanel.tokens
      return "ok=" + dimPanel.ok
        + " reading=" + (Model.barReading(dimPanel.snapshot, dimPanel.displayMode) || "-")
        + " mark=" + Model.markAsset(dimPanel.markMode)
        + " credits=" + (credits ? credits.used + "/" + credits.total : "?")
        + " reset=" + (dimPanel.term ? dimPanel.term.endAt : "?")
        + " usage=" + (tokens ? tokens.todayTotal + " tokens today, " + tokens.todayRuns + " runs, $" + tokens.todayCostUsd : "none")
        + " db=" + (tokens ? tokens.database : "?")
        + " error=" + JSON.stringify(dimPanel.errorText)
    }
  }

  // Runs whether or not the panel is open: the bar tooltip carries the reset
  // countdown too, and a stale one is worse than none.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: dimPanel.nowMs = Date.now()
  }

  // ------------------------------------------------------------------ bar

  // The project's own mark, then the reading. Not BarIconButton (a square slot
  // would clip the percentage) and not WidgetButton (it has no room for a
  // mark), so the button is assembled here with the same behaviour: tooltip on
  // hover, click target registered with the bar, urgent colour when the ledger
  // cannot be read.
  Item {
    id: button
    anchors.fill: parent
    implicitWidth: Math.round(barContent.implicitWidth + Style.spaceReal(8.5) * 2)
    implicitHeight: dimPanel.barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

    readonly property bool hasContent: true
    property var registeredBar: null

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(button)
      registeredBar = dimPanel.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(button)
    }

    function raiseTooltip() {
      if (dimPanel.bar && dimPanel.bar.showTooltip)
        dimPanel.bar.showTooltip(button, Model.barTooltip(dimPanel.snapshot, dimPanel.nowMs))
    }

    function dismissTooltip() {
      if (dimPanel.bar && dimPanel.bar.hideTooltip) dimPanel.bar.hideTooltip(button)
    }

    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(button)

    Connections {
      target: dimPanel
      function onBarChanged() { button.syncClickRegistration() }
    }

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(4)

      Item {
        id: markSlot
        // Match the glyphs beside it, not the icon canvas: a nerd-font icon
        // inks about 0.86em, while this mark fills ~0.94 of its own box, so
        // 0.92 * iconFont puts its ink at the neighbours' height (14px here)
        // instead of reading heavier than they do.
        readonly property int size: Math.max(Style.space(8), Math.round(Style.bar.iconFont * 0.92))
        width: size
        height: size
        anchors.verticalCenter: parent.verticalCenter

        Image {
          id: markImage
          anchors.fill: parent
          source: Qt.resolvedUrl(Model.markAsset(dimPanel.markMode))
          sourceSize.width: Math.round(markSlot.size * Screen.devicePixelRatio)
          sourceSize.height: Math.round(markSlot.size * Screen.devicePixelRatio)
          fillMode: Image.PreserveAspectFit
          smooth: true
          // Tinted mode samples this image as a texture instead of drawing it.
          visible: !dimPanel.markTinted
          layer.enabled: dimPanel.markTinted
        }

        MultiEffect {
          anchors.fill: markImage
          source: markImage
          visible: dimPanel.markTinted && markImage.status === Image.Ready
          // Colorization needs no padding, and the default padding is what let
          // the effect draw wider than the space the bar gave it.
          autoPaddingEnabled: false
          colorization: 1.0
          colorizationColor: dimPanel.markColor
        }

        // The asset is a file that could be missing or unreadable; a glyph is
        // always available.
        Text {
          visible: markImage.status !== Image.Ready
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: Model.barGlyph(dimPanel.snapshot)
          color: dimPanel.markColor
          font.family: dimPanel.fontFamily
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
        }
      }

      Text {
        id: barReading
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: dimPanel.barVertical ? "" : Model.barReading(dimPanel.snapshot, dimPanel.displayMode)
        color: dimPanel.markColor
        font.family: dimPanel.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !dimPanel.bar || dimPanel.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }

    MouseArea {
      id: barMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: button.raiseTooltip()
      onExited: button.dismissTooltip()
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) {
          button.dismissTooltip()
          dimPanel.refreshNow()
          return
        }
        button.dismissTooltip()
        dimPanel.toggle()
      }
    }
  }

  // --------------------------------------------------------------- panel

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: dimPanel
    bar: dimPanel.bar
    open: dimPanel.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(content.columnHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          dimPanel.switchPanel(dx)
          return
        }
        // The catcher consumes the arrow keys before the Flickable sees them,
        // so scrolling is handed to the body.
        content.scrollBy(dy * Style.space(56))
      }
      onTextKey: function(text) {
        if (text === "r" || text === "R") dimPanel.refreshNow()
      }
      onCloseRequested: dimPanel.close()
      onTabRequested: function(direction) { dimPanel.switchPanel(direction) }
    }

    // The body lives in its own file so it can be rendered and checked on its
    // own; the popup only positions and scrolls it.
    PanelContent {
      id: content
      anchors.fill: parent
      snapshot: dimPanel.snapshot
      errorText: dimPanel.errorText
      usageError: Model.usageErrorText(dimPanel.snapshot)
      loading: usage.loading
      fetchedAtMs: usage.fetchedAtMs
      nowMs: dimPanel.nowMs
      foreground: dimPanel.foreground
      urgentColor: dimPanel.urgent
      trackColor: dimPanel.track
      fontFamily: dimPanel.fontFamily
    }
  }
}
