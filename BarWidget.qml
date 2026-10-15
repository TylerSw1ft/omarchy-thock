import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar icon plus options panel. Left click opens the panel, right click
// switches sounds on or off, and scrolling changes the volume.
Panel {
  id: root
  moduleName: "tylersw1ft.thock"
  ipcTarget: "tylersw1ft.thock"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("tylersw1ft.thock") : null
  readonly property bool on: service ? service.enabled : false
  readonly property int percent: service ? Math.round(service.volume * 100) : 0
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string font: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function nudgeVolume(delta) {
    if (service) service.setVolume(service.volume + delta)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.on ? "󰌌" : "󰥻"
    dimmed: !root.on
    active: root.opened
    useActiveColor: false
    tooltipText: root.opened ? "" : (!root.service
      ? "Thock service is not running"
      : (root.on ? "Thock on · " + root.percent + "%" : "Thock off"))
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.service) root.service.toggle() }
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.nudgeVolume(delta > 0 ? 0.05 : -0.05) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.nudgeVolume(dx * 0.05) }
      onActivateRequested: if (root.service) root.service.toggle()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Text {
          visible: !root.service
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "The Thock service isn't running. Restart the shell with `omarchy restart shell`."
          color: root.fg
          font.family: root.font
          font.pixelSize: Style.font.bodySmall
        }

        Toggle {
          width: parent.width
          enabled: !!root.service
          label: "Typing sounds"
          description: root.on ? "Playing on every key" : "Off"
          checked: root.on
          foreground: root.fg
          fontFamily: root.font
          onClicked: if (root.service) root.service.toggle()
        }

        // ---------- Volume ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          enabled: !!root.service
          opacity: root.on ? 1.0 : 0.5

          Row {
            width: parent.width
            PanelSectionHeader {
              id: volumeHeader
              text: "VOLUME"
              foreground: root.fg
              fontFamily: root.font
            }
            Item { width: parent.width - volumeHeader.implicitWidth - volumeValue.implicitWidth; height: 1 }
            Text {
              id: volumeValue
              textFormat: Text.PlainText
              text: root.percent + "%"
              color: root.fg
              opacity: 0.7
              font.family: root.font
              font.pixelSize: Style.font.caption
              anchors.bottom: parent.bottom
            }
          }

          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 0.05
            maximum: 1
            step: 0.05
            value: root.service ? root.service.volume : 0.6
            onMoved: function(v) { if (root.service) root.service.setVolume(v) }
            onReleased: function(v) { if (root.service) root.service.preview() }
          }
        }

        // ---------- Depth and cream ----------
        LevelSlider {
          title: "DEPTH"
          labels: ["Brightest", "Bright", "Deep", "Deeper", "Deepest"]
          level: root.service ? root.service.depth : 2
          onPicked: function(v) { root.service.setDepth(v) }
        }

        LevelSlider {
          title: "CREAMY"
          labels: ["Crisp", "Natural", "Smooth", "Creamy", "Creamiest"]
          level: root.service ? root.service.cream : 3
          onPicked: function(v) { root.service.setCream(v) }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- Sound profile ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          enabled: !!root.service

          PanelSectionHeader {
            text: "SOUND"
            foreground: root.fg
            fontFamily: root.font
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property var options: root.service ? root.service.profiles : []
            readonly property real cellWidth: options.length > 0
              ? (width - spacing * (options.length - 1)) / options.length
              : 0

            Repeater {
              model: profileRow.options
              Button {
                required property var modelData
                width: profileRow.cellWidth
                text: modelData.label
                tooltipText: modelData.tooltip
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.font
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.service && root.service.profile === modelData.value
                onClicked: {
                  root.service.setProfile(modelData.value)
                  // Let the new samples load before the preview plays them.
                  previewDelay.restart()
                }
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Release sounds"
            description: root.service && !root.service.hasUpstroke
              ? "Thock has no release sound"
              : "A softer sound as each key comes up"
            checked: root.service ? root.service.upstroke : true
            foreground: root.fg
            fontFamily: root.font
            onClicked: {
              root.service.setUpstroke(!root.service.upstroke)
              root.service.preview()
            }
          }

          Button {
            width: parent.width
            text: "Preview"
            iconText: "󰐊"
            fontSize: Style.font.bodySmall
            foreground: root.fg
            fontFamily: root.font
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.service.preview()
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Right-click the icon to switch on or off · scroll to change volume"
          color: root.fg
          opacity: 0.5
          font.family: root.font
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Timer {
    id: previewDelay
    interval: 150
    onTriggered: if (root.service) root.service.preview()
  }

  component LevelSlider: Column {
    id: levelSlider
    property string title: ""
    property var labels: []
    property int level: 0
    signal picked(int value)

    width: parent.width
    spacing: Style.space(8)
    enabled: !!root.service

    Row {
      width: parent.width
      PanelSectionHeader {
        id: levelHeader
        text: levelSlider.title
        foreground: root.fg
        fontFamily: root.font
      }
      Item { width: parent.width - levelHeader.implicitWidth - levelValue.implicitWidth; height: 1 }
      Text {
        id: levelValue
        textFormat: Text.PlainText
        text: levelSlider.labels[levelSlider.level] || ""
        color: root.fg
        opacity: 0.7
        font.family: root.font
        font.pixelSize: Style.font.caption
        anchors.bottom: parent.bottom
      }
    }

    PanelSlider {
      bar: root.bar
      width: parent.width
      minimum: 0
      maximum: levelSlider.labels.length - 1
      step: 1
      integer: true
      tickCount: levelSlider.labels.length
      value: levelSlider.level
      onMoved: function(v) { if (root.service) levelSlider.picked(Math.round(v)) }
      onReleased: function(v) { previewDelay.restart() }
    }
  }
}
