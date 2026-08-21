pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "gobijan.ui-sounds"

  readonly property var soundService: bar?.shell?.serviceFor(root.moduleName)
  readonly property bool muted: !!(soundService && soundService.muted)
  readonly property bool alwaysShow: setting("alwaysShow", false) === true
  property bool indicatorItemHovered: false
  readonly property bool revealInactiveIndicators: alwaysShow
    || indicatorItemHovered
    || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)
  readonly property bool shown: muted || revealInactiveIndicators

  function setIndicatorItemHovered(hovered) {
    indicatorItemHovered = hovered
  }

  implicitWidth: root.vertical
    ? Math.max(indicator.implicitWidth, root.barSize)
    : (root.shown ? indicator.implicitWidth : 0)
  implicitHeight: root.vertical
    ? (root.shown ? indicator.implicitHeight : 0)
    : Math.max(indicator.implicitHeight, root.barSize)
  clip: true

  BarIndicator {
    id: indicator
    bar: root.bar
    moduleName: root.moduleName
    settings: root.settings
    indicatorHost: root
    active: root.muted
    activeText: "󰯉"
    inactiveText: "󰯉"
    activeTooltipText: "Enable Interface Sounds"
    inactiveTooltipText: "Mute Interface Sounds"
    iconComponent: invaderIcon
    onPressed: function() {
      if (root.soundService && typeof root.soundService.writeEnabled === "function")
        root.soundService.writeEnabled(!root.soundService.playbackEnabled)
    }
  }

  Component {
    id: invaderIcon

    Item {
      OpticalGlyph {
        anchors.fill: parent
        text: "󰯉"
        fontFamily: indicator.fontFamily
        fontSize: indicator.fontSize
        color: indicator.foreground
      }

      Rectangle {
        visible: root.muted
        anchors.centerIn: parent
        width: parent.width * 1.05
        height: 1
        radius: 0.5
        opacity: 0.8
        antialiasing: true
        color: indicator.foreground
        rotation: -45
      }
    }
  }
}
