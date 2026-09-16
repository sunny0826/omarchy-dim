import QtQuick
import Quickshell.Io
import "Model.js" as Model

// The widget's data half. It owns the one process that reads usage, the timer
// that re-reads it, and the snapshot that both the bar label and the panel
// draw. Panel.qml stays layout-only because everything with a decision in it
// lives here.
//
// The command is the plugin's own collector, never the API: credentials stay
// with the CLI, and the collector keeps working when the widget's QML changes.
Item {
  id: root
  visible: false

  property var settings: ({})

  readonly property string scriptPath: Model.fileUrlToPath(Qt.resolvedUrl("scripts/dim-usage"))
  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 120)))
  readonly property string dimBinary: String(setting("dimBinary", ""))

  // The last complete snapshot, or null before the first read lands.
  property var snapshot: null
  property bool loading: false
  property double fetchedAtMs: 0
  // Set when the collector could not be run or did not answer with JSON; the
  // snapshot's own `error` covers "the CLI answered, but with a failure".
  property string transportError: ""
  property bool runQueued: false
  // Set when the watchdog killed a read, so the exit that follows does not
  // overwrite the real reason with a generic one.
  property bool timedOut: false

  // Whether the CLI exists. Until the first read lands the widget assumes yes,
  // so it does not flicker in and out on every shell start.
  readonly property bool installed: snapshot ? snapshot.dimFound === true : true
  readonly property bool ok: snapshot !== null && snapshot.ok === true
  readonly property string error: {
    if (transportError !== "") return transportError
    if (snapshot && snapshot.ok !== true) return String(snapshot.error || "usage unavailable")
    return ""
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    // A refresh asked for while one is in flight is folded into a single
    // follow-up run, so asking twice never queues two extra reads.
    if (process.running) {
      runQueued = true
      return
    }
    process.command = Model.usageCommand(scriptPath, { dimBinary: dimBinary })
    // A hung read is reported by whichever layer notices first: the collector
    // gives up on `dim usage` itself, and this watchdog only covers the
    // collector going quiet for a reason of its own.
    timedOut = false
    loading = true
    process.running = true
    watchdog.restart()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // `dim usage` talks to the network. A read that never returns must not leave
  // the widget loading forever.
  Timer {
    id: watchdog
    interval: 45000
    repeat: false
    onTriggered: {
      if (!process.running) return
      root.timedOut = true
      process.running = false
      root.loading = false
      root.transportError = "Reading usage timed out"
    }
  }

  Process {
    id: process
    running: false

    stdout: StdioCollector {
      id: output
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: errors
      waitForEnd: true
    }

    onExited: function(exitCode) {
      watchdog.stop()
      root.loading = false


      // The collector prints a snapshot even when it exits nonzero (that is how
      // "dim is not signed in" reaches the panel), so parse first and only fall
      // back to the transport error when there is nothing to parse.
      var parsed = null
      try {
        parsed = JSON.parse(String(output.text || ""))
      } catch (error) {
        parsed = null
      }

      if (parsed !== null && typeof parsed === "object") {
        root.snapshot = parsed
        root.fetchedAtMs = Date.now()
        root.transportError = ""
      } else if (root.timedOut) {
        console.warn("sunny0826.dim", "reading usage timed out")
        // The watchdog already said why; the killed process has nothing to add.
        root.timedOut = false
      } else {
        var detail = String(errors.text || "").trim()
        root.transportError = detail !== "" ? detail : "Reading usage failed (exit " + exitCode + ")"
        // The panel shows this too; the shell log is for "why is the bar icon
        // an alert mark" without opening anything.
        console.warn("sunny0826.dim", root.transportError)
      }

      if (root.runQueued) {
        root.runQueued = false
        root.refresh()
      }
    }
  }
}
