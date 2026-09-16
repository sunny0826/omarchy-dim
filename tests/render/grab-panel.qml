// Renders the plugin's real panel body into a PNG so the layout can be looked
// at without a screenshot tool. Both plugin files load by path — the same
// files the shell loads — and the snapshot is live: Usage.qml runs the real
// collector, so the pixels come from current data.
import QtQuick
import QtQuick.Window
// Screen is the Window's attached property, used for the pixel ratio above.
import Quickshell
import qs.Commons

ShellRoot {
  id: harness

  // Set by `make probe` / `make render`; there is no sensible default because
  // the harness loads this plugin's own files by path.
  readonly property string pluginDir: Quickshell.env("HARNESS_PLUGIN_DIR") || ""
  readonly property string pluginUrl: "file://" + pluginDir + "/"

  Component.onCompleted: if (pluginDir === "")
    console.warn("render harness", "set HARNESS_PLUGIN_DIR to the plugin directory")
  readonly property string dimOverride: Quickshell.env("HARNESS_DIM_BIN") || ""

  Loader {
    id: usageLoader
    source: harness.pluginUrl + "Usage.qml"
    onLoaded: usageLoader.item.settings = ({
      refreshIntervalSec: 3600,
      barDisplay: "Remaining",
      barMark: "Brand",
      dimBinary: harness.dimOverride
    })
  }

  Window {
    id: win
    // Deliberately larger than the panel: the grab of an item cannot exceed
    // the window surface, and the body lays out wider than the popup's width.
    width: 380 + Style.spacing.popupPadding * 2
    height: 900
    visible: true
    color: Color.popups.background

    Loader {
      id: bodyLoader
      // An explicit width, not anchors: the body lays out at exactly the size
      // it is grabbed at, so nothing is clipped by whatever units the window
      // surface happens to use.
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.popupPadding
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

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: {
      var usage = usageLoader.item
      var body = bodyLoader.item
      if (!usage || !usage.snapshot || !body) return
      bodyLoader.apply()
      console.log("theme fg=" + Color.foreground + " bg=" + Color.background + " popups=" + Color.popups.background
        + " theme=" + Color.currentThemePath)
      var name = Quickshell.env("HARNESS_OUT") || "/tmp/dim-check/panel.png"
      // Grab the whole window at its natural device resolution: asking for an
      // explicit size lands in mixed units and stretches the image.
      // Larger than the body's own size on purpose: a target smaller than the
      // content silently clips the right-hand values. The composer crops the
      // transparent margin back off.
      var ratio = 1
      body.grabToImage(function(result) {
        console.log("GRAB " + name + " saved=" + result.saveToFile(name)
          + " body=" + body.width + "x" + body.columnHeight + " ratio=" + ratio)
        Qt.quit()
      }, Qt.size(720, 1000))
    }
  }
}
