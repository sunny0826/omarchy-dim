pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The panel's body: the hero, the meters, the usage table, and the wording
// around them. It owns no window, no bar, and no process — Panel.qml hosts it
// inside the attached popup, and the scratch render harness instantiates it on
// its own to check the layout without a desktop session.
Item {
  id: content

  // Filled by the host.
  property var snapshot: null
  property string errorText: ""
  property string usageError: ""
  property bool loading: false
  property double fetchedAtMs: 0
  property double nowMs: Date.now()
  property color foreground: Color.foreground
  property color urgentColor: Color.urgent
  property color dimColor: Qt.darker(foreground, 1.55)
  property color trackColor: Style.selectedFillFor(foreground, Color.accent, urgentColor)
  property string fontFamily: Style.font.family

  readonly property bool hasData: snapshot !== null
  readonly property bool ok: snapshot !== null && snapshot.ok === true
  readonly property var plan: snapshot ? snapshot.plan : null
  readonly property var subscription: snapshot ? snapshot.subscription : null
  readonly property var credits: snapshot ? snapshot.credits : null
  readonly property var term: snapshot ? snapshot.term : null
  readonly property var features: snapshot ? snapshot.features : null
  readonly property var models: snapshot ? snapshot.models : null
  readonly property var tokens: snapshot ? snapshot.tokens : null
  readonly property bool alarming: Model.alarming(snapshot)
  readonly property var featureRows: Model.featureRows(features)
  readonly property var dayRows: Model.dayRows(tokens, nowMs)
  readonly property var tokenModelRows: Model.modelRows(tokens, 3)
  readonly property bool hasCredits: credits !== null && Number(credits.total) > 0
  readonly property bool hasFeatures: featureRows.length > 0
  readonly property bool hasTokens: tokens !== null

  // How tall the body wants to be, so the host can size the popup to it.
  readonly property real columnHeight: bodyColumn.implicitHeight
  implicitHeight: columnHeight

  function scrollBy(dy) {
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    panelFlick.contentY = Model.clamp(panelFlick.contentY + dy, 0, maxY)
  }

  function resetScroll() {
    panelFlick.contentY = 0
  }

  Flickable {
    id: panelFlick
    anchors.fill: parent
    contentWidth: width
    contentHeight: bodyColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: bodyColumn
      width: panelFlick.width
      spacing: Style.space(12)

      // ---------- Hero: the tool, the plan, what it costs ----------

      PanelHero {
        id: hero
        width: parent.width
        title: "DimAgent"
        meta: content.plan && content.plan.name ? String(content.plan.name) : "Subscription"
        detail: content.plan && Number(content.plan.priceAmount) > 0
          ? Model.formatPrice(content.plan.priceAmount, content.plan.currency, content.plan.interval)
          : ""
        foreground: content.foreground
        fontFamily: content.fontFamily

        iconComponent: Component {
          Item {
            width: Style.font.display
            height: Style.font.display

            // The project's logo, as published. A glyph stands in if the icon
            // cannot be loaded.
            Image {
              id: heroLogo
              anchors.fill: parent
              source: Qt.resolvedUrl("assets/dim-logo.png")
              sourceSize.width: Math.round(Style.font.display * Screen.devicePixelRatio)
              sourceSize.height: Math.round(Style.font.display * Screen.devicePixelRatio)
              fillMode: Image.PreserveAspectFit
              smooth: true
              visible: status === Image.Ready
            }

            Text {
              visible: heroLogo.status !== Image.Ready
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: Model.GLYPH
              color: content.foreground
              font.family: content.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }
      }

      Text {
        visible: !content.hasData
        width: parent.width
        topPadding: Style.space(12)
        textFormat: Text.PlainText
        text: content.loading ? "Reading usage…" : "No usage recorded yet."
        color: content.dimColor
        font.family: content.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      NoticeCard {
        visible: content.hasData && !content.ok
        width: parent.width
        urgentColor: content.urgentColor
        foreground: content.foreground
        fontFamily: content.fontFamily
        title: content.errorText === "" ? "Usage unavailable" : content.errorText
        body: Model.errorHelp(content.snapshot)
      }

      // ---------- Credits: the ledger, and when it refills ----------

      Column {
        id: creditsSection
        width: parent.width
        spacing: Style.space(10)
        visible: content.ok && content.hasCredits

        PanelSeparator { width: parent.width; foreground: content.foreground }
        PanelSectionHeader { width: parent.width; text: "CREDITS"; foreground: content.foreground; fontFamily: content.fontFamily }

        StatRow {
          width: parent.width
          label: "Used"
          value: Model.creditUsedText(content.credits)
          suffix: Model.percentText(Model.usedPercent(content.credits))
          alarming: content.alarming
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        Meter {
          width: parent.width
          value: Model.usedPercent(content.credits)
          alarming: content.alarming
          trackColor: content.trackColor
          fillColor: content.foreground
          urgentColor: content.urgentColor
        }

        StatRow {
          width: parent.width
          label: "Remaining"
          value: Model.creditRemainingText(content.credits)
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        StatRow {
          width: parent.width
          label: "Resets in"
          value: Model.resetText(content.term ? content.term.endAt : "", content.nowMs)
          caption: Model.formatDate(content.term ? content.term.endAt : "")
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }
      }

      // ---------- Allowances: what else the plan grants ----------

      Column {
        id: allowanceSection
        width: parent.width
        spacing: Style.space(10)
        visible: content.ok && content.hasFeatures

        PanelSeparator { width: parent.width; foreground: content.foreground }
        PanelSectionHeader { width: parent.width; text: "ALLOWANCES"; foreground: content.foreground; fontFamily: content.fontFamily }

        Repeater {
          model: content.featureRows

          Column {
            id: featureDelegate
            required property var modelData
            width: allowanceSection.width
            spacing: Style.space(6)

            StatRow {
              width: parent.width
              label: String(featureDelegate.modelData.label || "")
              value: String(featureDelegate.modelData.value || "")
              caption: Model.resetText(featureDelegate.modelData.endAt, content.nowMs)
              foreground: content.foreground
              dimColor: content.dimColor
              urgentColor: content.urgentColor
              fontFamily: content.fontFamily
            }

            Meter {
              width: parent.width
              value: Number(featureDelegate.modelData.fraction || 0)
              alarming: Number(featureDelegate.modelData.fraction || 0) >= 0.9
              trackColor: content.trackColor
              fillColor: content.foreground
              urgentColor: content.urgentColor
            }
          }
        }
      }

      // ---------- Local usage: what Dim itself has spent ----------

      Column {
        id: usageSection
        width: parent.width
        spacing: Style.space(10)
        visible: content.hasData && (content.hasTokens || content.usageError !== "")

        PanelSeparator { width: parent.width; foreground: content.foreground }
        PanelSectionHeader { width: parent.width; text: "LOCAL USAGE"; foreground: content.foreground; fontFamily: content.fontFamily }

        // The credits half can be fine while the local ledger is not; say so
        // here rather than dropping the whole section.
        Text {
          width: parent.width
          visible: content.usageError !== ""
          textFormat: Text.PlainText
          text: content.usageError
          color: content.urgentColor
          font.family: content.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        StatRow {
          width: parent.width
          visible: content.hasTokens
          label: "Today"
          value: Model.formatCount(content.tokens ? content.tokens.todayTotal : 0)
          caption: content.tokens
            ? Model.runText(content.tokens.todayRuns) + Model.SEP
              + Model.sessionText(content.tokens.todaySessions) + Model.SEP
              + Model.formatCost(content.tokens.todayCostUsd)
            : ""
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        Repeater {
          model: content.hasTokens ? content.dayRows : []

          DayRow {
            id: dayDelegate
            required property var modelData
            width: usageSection.width
            day: dayDelegate.modelData
            foreground: content.foreground
            dimColor: content.dimColor
            trackColor: content.trackColor
            fontFamily: content.fontFamily
          }
        }

        StatRow {
          width: parent.width
          visible: content.hasTokens
          label: "This month"
          value: Model.formatCount(content.tokens ? content.tokens.windowTotal : 0)
          caption: content.tokens
            ? Model.runText(content.tokens.windowRuns) + Model.SEP
              + Model.dayText(content.tokens.activeDays) + Model.SEP
              + Model.formatCost(content.tokens.windowCostUsd)
            : ""
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        Repeater {
          model: content.hasTokens ? content.tokenModelRows : []

          ModelRow {
            id: modelDelegate
            required property var modelData
            width: usageSection.width
            entry: modelDelegate.modelData
            foreground: content.foreground
            dimColor: content.dimColor
            trackColor: content.trackColor
            fontFamily: content.fontFamily
          }
        }

        Text {
          width: parent.width
          visible: content.hasTokens && text !== ""
          textFormat: Text.PlainText
          text: Model.usageSourceCaption(content.tokens)
          color: content.dimColor
          font.family: content.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      // ---------- Plan: what is being paid for ----------

      Column {
        id: planSection
        width: parent.width
        spacing: Style.space(10)
        visible: content.ok

        PanelSeparator { width: parent.width; foreground: content.foreground }
        PanelSectionHeader { width: parent.width; text: "PLAN"; foreground: content.foreground; fontFamily: content.fontFamily }

        StatRow {
          width: parent.width
          label: "Status"
          value: Model.planDetail(content.subscription)
          alarming: content.subscription !== null
            && (content.subscription.cancelAtPeriodEnd === true
                || String(content.subscription.status) !== "active")
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        StatRow {
          width: parent.width
          label: "Price"
          value: content.plan && Number(content.plan.priceAmount) > 0
            ? Model.formatPrice(content.plan.priceAmount, content.plan.currency, content.plan.interval)
            : "—"
          caption: content.plan ? String(content.plan.provider || "") : ""
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        StatRow {
          width: parent.width
          label: "Models"
          value: Model.modelsText(content.models)
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        StatRow {
          width: parent.width
          label: "Compact model"
          value: content.snapshot && content.snapshot.compactModel
            ? String(content.snapshot.compactModel)
            : "—"
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }

        StatRow {
          width: parent.width
          label: "Account"
          value: content.snapshot && Number(content.snapshot.accountId) > 0
            ? "#" + content.snapshot.accountId
            : "—"
          foreground: content.foreground
          dimColor: content.dimColor
          urgentColor: content.urgentColor
          fontFamily: content.fontFamily
        }
      }

      Text {
        id: footer
        width: parent.width
        textFormat: Text.PlainText
        text: {
          var parts = []
          var updated = Model.updatedText(content.fetchedAtMs, content.nowMs)
          if (updated !== "") parts.push(updated)
          if (content.loading) parts.push("refreshing…")
          parts.push("r refresh")
          parts.push("esc close")
          return parts.join(Model.SEP)
        }
        color: content.dimColor
        font.family: content.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // The used/allowance bar: a rounded track with a fill that follows the
  // theme's foreground and turns urgent near the end.
  component Meter: Item {
    id: meter

    property real value: 0
    property bool alarming: false
    property color trackColor: Color.foreground
    property color fillColor: Color.foreground
    property color urgentColor: Color.urgent
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: meter.trackColor
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * Model.clamp(meter.value, 0, 1)
      color: meter.alarming ? meter.urgentColor : meter.fillColor

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }

  // A label on the left, a value on the right, an optional caption under it.
  component StatRow: Item {
    id: row

    property string label: ""
    property string value: ""
    property string suffix: ""
    property string caption: ""
    property bool alarming: false
    property color foreground: Color.foreground
    property color dimColor: Color.foreground
    property color urgentColor: Color.urgent
    property string fontFamily: Style.font.family

    width: parent ? parent.width : implicitWidth
    implicitHeight: labelRow.implicitHeight
      + (row.caption !== "" ? captionText.implicitHeight + Style.space(2) : 0)

    // The label and the value are centered against each other in a row of
    // their own; the caption sits under both, so a row with a caption does not
    // drift out of alignment with one without.
    Item {
      id: labelRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      implicitHeight: Math.max(labelText.implicitHeight, valueGroup.implicitHeight)

      Text {
        id: labelText
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: valueGroup.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Row {
        id: valueGroup
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        Text {
          id: valueText
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: row.value
          color: row.alarming ? row.urgentColor : row.foreground
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          visible: row.suffix !== ""
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: row.suffix
          color: row.alarming ? row.urgentColor : row.dimColor
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      id: captionText
      visible: row.caption !== ""
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: labelRow.bottom
      anchors.topMargin: Style.space(2)
      text: row.caption
      color: row.dimColor
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // One day of the local usage history. The bar scales to the busiest day in
  // the window, so a quiet week still shows its shape.
  component DayRow: Item {
    id: dayRow

    property var day: ({})
    property color foreground: Color.foreground
    property color dimColor: Color.foreground
    property color trackColor: Color.foreground
    property string fontFamily: Style.font.family

    readonly property bool isToday: day.isToday === true

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight)

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
      text: String(dayRow.day.label || "")
      color: dayRow.foreground
      font.family: dayRow.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: dayRow.isToday
      elide: Text.ElideRight
    }

    Rectangle {
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: dayRow.trackColor

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * Model.clamp(Number(dayRow.day.fraction || 0), 0, 1)
        color: Qt.rgba(dayRow.foreground.r, dayRow.foreground.g, dayRow.foreground.b, 0.55)
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: Model.formatCount(dayRow.day.total)
      color: dayRow.foreground
      font.family: dayRow.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.isToday
    }
  }

  // A model's share of the window, with the bar behind the row rather than
  // beside it: the rows are the chart.
  component ModelRow: Item {
    id: modelRow

    property var entry: ({})
    property color foreground: Color.foreground
    property color dimColor: Color.foreground
    property color trackColor: Color.foreground
    property string fontFamily: Style.font.family

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(modelLabel.implicitHeight, modelValue.implicitHeight) + Style.space(6)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Qt.rgba(modelRow.foreground.r, modelRow.foreground.g, modelRow.foreground.b, 0.05)

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: parent.radius
        width: parent.width * Model.clamp(Number(modelRow.entry.fraction || 0), 0, 1)
        color: Qt.rgba(modelRow.foreground.r, modelRow.foreground.g, modelRow.foreground.b, 0.14)
      }
    }

    Text {
      id: modelLabel
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.right: modelValue.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      text: String(modelRow.entry.label || "")
      color: modelRow.foreground
      font.family: modelRow.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      id: modelValue
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: Model.formatCount(modelRow.entry.total) + " · " + Model.runText(modelRow.entry.runs)
      color: modelRow.foreground
      font.family: modelRow.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: String(modelRow.entry.detail || "")
      fontFamily: modelRow.fontFamily
    }
  }

  // An error card: what went wrong, and the one thing to try next.
  component NoticeCard: BorderSurface {
    id: notice

    property color urgentColor: Color.urgent
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    property string title: ""
    property string body: ""

    color: Qt.rgba(notice.urgentColor.r, notice.urgentColor.g, notice.urgentColor.b, 0.10)
    borderSpec: Border.flat(Qt.rgba(notice.urgentColor.r, notice.urgentColor.g, notice.urgentColor.b, 0.35),
                            Math.max(1, Style.space(1)))
    radius: Style.cornerRadius
    topPadding: Style.spacing.controlPaddingX
    rightPadding: Style.spacing.controlPaddingX
    bottomPadding: Style.spacing.controlPaddingX
    leftPadding: Style.spacing.controlPaddingX
    implicitHeight: noticeColumn.implicitHeight + contentTopInset + contentBottomInset

    Column {
      id: noticeColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: notice.contentLeftInset
      anchors.rightMargin: notice.contentRightInset
      anchors.topMargin: notice.contentTopInset
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: notice.title
        color: notice.foreground
        font.family: notice.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: notice.body !== ""
        textFormat: Text.PlainText
        text: notice.body
        color: notice.urgentColor
        font.family: notice.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
    }
  }
}
