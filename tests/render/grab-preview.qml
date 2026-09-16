// Renders the plugin's market listing preview: the bar button and the panel
// body together, on the active theme's background, drawn by the real
// components with live data.
//
//   HARNESS_PLUGIN_DIR=<plugin dir> HARNESS_OUT=<file.png> quickshell -p tests/render/grab-preview.qml
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui

ShellRoot {
  id: harness

  readonly property string pluginDir: Quickshell.env("HARNESS_PLUGIN_DIR") || ""
  readonly property string pluginUrl: "file://" + pluginDir + "/"
  readonly property string mode: Quickshell.env("HARNESS_MARK") || "Mono"

  Component.onCompleted: if (pluginDir === "")
    console.warn("render harness", "set HARNESS_PLUGIN_DIR to the plugin directory")

  QtObject {
    id: fakeBar
    property color foreground: Color.foreground
    property color background: Color.background
    property color urgent: Color.urgent
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property int barSize: Style.bar.sizeHorizontal
    property string position: "top"
    property var activePopout: null
    property var clickTargets: []
    function run(command) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function requestPopout(owner) { return true }
    function releasePopout(owner) {}
    function targetBelongsToWindow(target) { return false }
    function switchPanelFrom(owner, direction) { return false }
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
  }

  Loader {
    id: usageLoader
    source: harness.pluginUrl + "Usage.qml"
    onLoaded: usageLoader.item.settings = ({
      refreshIntervalSec: 3600,
      barDisplay: "Remaining",
      barMark: harness.mode,
      dimBinary: ""
    })
  }

  Window {
    id: win
    width: preview.width
    height: preview.height
    visible: true
    color: Color.background

    // The desktop backdrop, then the bar strip, then the panel card — the same
    // arrangement the shell produces.
    Rectangle {
      id: preview
      width: 420
      height: barStrip.height + panelCard.height + Style.space(18) * 2
      color: Color.background

      Rectangle {
        id: barStrip
        anchors.top: parent.top
        anchors.left: parent.left
        width: Style.space(220)
        height: Style.bar.sizeHorizontal + Style.space(10)
        color: Qt.darker(Color.background, 1.1)

        Loader {
          id: buttonLoader
          anchors.centerIn: parent
          source: harness.pluginUrl + "Panel.qml"
          onLoaded: {
            buttonLoader.item.bar = fakeBar
            buttonLoader.item.moduleName = "sunny0826.dim"
            buttonLoader.item.settings = ({ barDisplay: "Remaining", barMark: harness.mode })
          }
        }
      }

      BorderSurface {
        id: panelCard
        anchors.top: barStrip.bottom
        anchors.topMargin: Style.space(18)
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Style.space(18) * 2
        height: bodyLoader.item
          ? bodyLoader.item.columnHeight + Style.spacing.popupPadding * 2 + contentTopInset + contentBottomInset
          : 0
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        Loader {
          id: bodyLoader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: panelCard.contentLeftInset
          anchors.rightMargin: panelCard.contentRightInset
          anchors.topMargin: panelCard.contentTopInset
          height: item ? item.columnHeight : 0

          property alias bodyItem: bodyLoader.item
          source: harness.pluginUrl + "PanelContent.qml"
          onLoaded: bodyLoader.apply()
          function apply() {
            var item = bodyLoader.item
            var usage = usageLoader.item
            if (!item || !usage) return
            item.snapshot = usage.snapshot
            item.errorText = usage.error
            item.usageError = usage.snapshot && usage.snapshot.tokenError ? String(usage.snapshot.tokenError) : ""
            item.loading = usage.loading
            item.fetchedAtMs = usage.fetchedAtMs
            item.nowMs = Date.now()
            item.foreground = Color.foreground
            item.urgentColor = Color.urgent
            item.trackColor = Style.selectedFillFor(Color.foreground, Color.accent, Color.urgent)
            item.fontFamily = Style.font.family
          }
        }
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: {
      if (!usageLoader.item || !usageLoader.item.snapshot) return
      bodyLoader.apply()
      // The card's height follows the body's, so re-fit the scene before
      // grabbing rather than relying on the first layout pass.
      preview.height = barStrip.height + Style.space(18) * 2
        + (bodyLoader.item ? bodyLoader.item.columnHeight + Style.spacing.popupPadding * 2 : 0)
      var name = Quickshell.env("HARNESS_OUT") || (pluginDir + "preview.png")
      // Grab at the window's logical size: passing item geometry lands in
      // device pixels and renders the scene at half scale in the corner.
      preview.grabToImage(function(result) {
        console.log("GRAB " + name + " saved=" + result.saveToFile(name)
          + " scene=" + preview.width + "x" + preview.height)
        Qt.quit()
      }, Qt.size(preview.width, preview.height))
    }
  }
}
