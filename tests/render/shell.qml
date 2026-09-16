// Scratch harness: loads the plugin's real QML files in an isolated
// quickshell instance, with a stub bar, so binding errors surface without
// touching the running shell. Not part of the plugin.
import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  id: harness

  // What Bar.qml injects into a widget. Enough of it for the panel to bind
  // against; nothing here talks back to a real bar.
  QtObject {
    id: fakeBar
    property color foreground: Color.foreground
    property color background: Color.background
    property color urgent: Color.urgent
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property bool vertical: harness.vertical
    property bool foregroundAnimationEnabled: false
    property int barSize: 26
    property string position: "top"
    property var activePopout: null
    property var clickTargets: []
    function run(command) { console.log("HARNESS bar.run:", command) }
    function showTooltip(target, text) { console.log("HARNESS tooltip: " + text) }
    function hideTooltip(target) {}
    function requestPopout(owner) { return true }
    function releasePopout(owner) {}
    function targetBelongsToWindow(target) { return false }
    function switchPanelFrom(owner, direction) { console.log("HARNESS switchPanelFrom " + direction); return false }
  }

  property bool vertical: false
  property int ticks: 0

  // Set by `make probe` / `make render`; there is no sensible default because
  // the harness loads this plugin's own files by path.
  readonly property string pluginDir: Quickshell.env("HARNESS_PLUGIN_DIR") || ""
  readonly property string pluginUrl: "file://" + pluginDir + "/"

  Component.onCompleted: if (pluginDir === "")
    console.warn("render harness", "set HARNESS_PLUGIN_DIR to the plugin directory")
  readonly property string dimOverride: Quickshell.env("HARNESS_DIM_BIN") || ""
  readonly property string display: Quickshell.env("HARNESS_DISPLAY") || "Remaining"
  readonly property string mark: Quickshell.env("HARNESS_MARK") || "Brand"

  Loader {
    id: usageLoader
    source: harness.pluginUrl + "Usage.qml"
    onLoaded: {
      item.settings = ({ refreshIntervalSec: 3600, barDisplay: harness.display, barMark: harness.mark, dimBinary: harness.dimOverride })
      item.refresh()
    }
  }

  Loader {
    id: panelLoader
    source: harness.pluginUrl + "Panel.qml"
    onLoaded: {
      item.bar = fakeBar
      item.moduleName = "sunny0826.dim"
      item.settings = ({ barDisplay: harness.display, barMark: harness.mark, dimBinary: harness.dimOverride })
      item.open()
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: {
      harness.ticks++
      var usage = usageLoader.item
      var panel = panelLoader.item
      if (!usage || !panel) return

      if (usage.snapshot) {
        var s = usage.snapshot
        console.log("HARNESS snapshot ok=" + s.ok + " dimFound=" + s.dimFound
          + " credits=" + (s.credits ? s.credits.used + "/" + s.credits.total : "?")
          + " today=" + (s.tokens ? s.tokens.todayTotal : "none")
          + " runs=" + (s.tokens ? s.tokens.todayRuns : "?")
          + " cost=" + (s.tokens ? s.tokens.todayCostUsd : "?")
          + " db=" + (s.tokens ? s.tokens.database : "none")
          + " err=" + JSON.stringify(s.error) + " tokenErr=" + JSON.stringify(s.tokenError || ""))
        console.log("HARNESS displayMode=" + panel.displayMode
          + " markMode=" + panel.markMode
          + " markTinted=" + panel.markTinted
          + " markAlarming=" + panel.markAlarming)
      }

      if (harness.ticks === 1) {
        // Flip the bar orientation mid-flight: the label must fall back to the
        // glyph and the bindings must not error.
        harness.vertical = true
      } else if (harness.ticks === 2) {
        console.log("HARNESS vertical=" + panel.barVertical + " markMode=" + panel.markMode
          + " markTinted=" + panel.markTinted)
      }

      console.log("HARNESS tick " + harness.ticks
        + " visible=" + panel.visible
        + " ok=" + panel.ok
        + " hasCredits=" + panel.hasCredits
        + " featureRows=" + panel.featureRows.length
        + " dayRows=" + panel.dayRows.length
        + " modelRows=" + panel.tokenModelRows.length
        + " alarming=" + panel.alarming
        + " error=" + JSON.stringify(panel.errorText)
        + " usageErr=" + JSON.stringify(panel.usageError)
        + " markColor=" + panel.markColor)

      if ((usage.snapshot !== null && harness.ticks >= 3) || harness.ticks >= (Number(Quickshell.env("HARNESS_TICKS")) || 10)) {
        console.log("HARNESS done")
        Qt.quit()
      }
    }
  }
}
