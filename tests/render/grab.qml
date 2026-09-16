// Renders the plugin's real bar button off-screen and writes a PNG, so the
// logo and the reading can be looked at without a screenshot tool.
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons

ShellRoot {
  id: harness

  // The plugin's own location, so the harness works from any checkout.
  // Set by `make probe` / `make render`; there is no sensible default because
  // the harness loads this plugin's own files by path.
  readonly property string pluginDir: Quickshell.env("HARNESS_PLUGIN_DIR") || ""
  readonly property string pluginUrl: "file://" + pluginDir + "/"

  Component.onCompleted: if (pluginDir === "")
    console.warn("render harness", "set HARNESS_PLUGIN_DIR to the plugin directory")

  property string mode: Quickshell.env("HARNESS_MARK") || "Mono"
  property string display: Quickshell.env("HARNESS_DISPLAY") || "Remaining"
  property int shots: 0

  QtObject {
    id: fakeBar
    property color foreground: Color.foreground
    property color background: Color.background
    property color urgent: Color.urgent
    property color barForeground: Color.foreground
    property string fontFamily: Style.font.family
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property int barSize: 26
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

  Window {
    id: win
    width: 320
    height: 40
    visible: true
    color: Color.background

    Loader {
      id: panelLoader
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      source: harness.pluginUrl + "Panel.qml"
      onLoaded: {
        item.bar = fakeBar
        item.moduleName = "sunny0826.dim"
        item.settings = ({ barDisplay: harness.display, barMark: harness.mode })
      }
    }
  }

  Timer {
    interval: 2500
    running: true
    repeat: false
    onTriggered: {
      var panel = panelLoader.item
      if (!panel) { console.log("GRAB no panel"); Qt.quit(); return }
      panel.grabToImage(function(result) {
        var path = (Quickshell.env("HARNESS_OUT") || "/tmp/dim-check/bar-") + harness.mode.toLowerCase() + ".png"
        console.log("GRAB " + path + " " + result.saveToFile(path)
          + " size=" + result.width + "x" + result.height)
        Qt.quit()
      }, Qt.size(Math.round(panel.implicitWidth), Math.round(panel.implicitHeight)))
    }
  }
}
