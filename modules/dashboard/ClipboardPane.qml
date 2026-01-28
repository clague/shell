pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // Pane sizing: the dashboard loader will size this item as needed
    implicitWidth: Math.max(840, layout.implicitWidth)
    implicitHeight: layout.implicitHeight

    readonly property int minCellWidth: 200 + Appearance.spacing.normal
    readonly property int columnsCount: Math.max(1, Math.floor(width / minCellWidth))
    readonly property int effectiveCellWidth: Math.floor(width / columnsCount)
    readonly property int cellHeight: 180

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Appearance.padding.normal
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            Column {
                spacing: -Appearance.spacing.smaller

                StyledText {
                    text: qsTr("%1 items").arg(Clipboard.history.values.length)
                    font.pointSize: Appearance.font.size.large
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                icon: "delete_sweep"
                type: IconButton.Tonal
                onClicked: Clipboard.clearHistory(true) // preserve pinned by default
            }

            IconButton {
                icon: "delete_forever"
                type: IconButton.Text
                onClicked: Clipboard.clearHistory(false) // force clear all
            }
        }

        // Grid area
        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: Math.max(400, Math.ceil(Math.max(1, Clipboard.history.values.length) / columnsCount) * (root.cellHeight + Appearance.spacing.normal))
            radius: Appearance.rounding.normal
            color: Colours.tPalette.m3surfaceContainer

            GridView {
                id: grid
                anchors.fill: parent
                anchors.margins: Appearance.padding.normal / 2
                clip: true

                model: Clipboard.history
                cellWidth: root.effectiveCellWidth - Appearance.spacing.normal
                cellHeight: root.cellHeight
                //spacing: Appearance.spacing.normal / 2

                interactive: true

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: grid
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    property bool pinned: false

                    width: grid.cellWidth
                    height: grid.cellHeight

                    readonly property real innerMargin: Appearance.spacing.small
                    readonly property real itemRadius: Appearance.rounding.normal

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Appearance.padding.normal / 2
                        radius: parent.itemRadius
                        color: "transparent"
                        border.width: parent.pinned ? 2 : 0
                        border.color: Colours.palette.m3primary
                        opacity: 1
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Colours.palette.m3onSurface
                        radius: parent.itemRadius
                        opacity: 0.05

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.anim.durations.small
                            }
                        }
                    }

                    StyledRect {
                        id: card
                        anchors.fill: parent
                        anchors.margins: parent.innerMargin
                        radius: parent.itemRadius
                        color: Colours.tPalette.m3surfaceContainer
                        smooth: true
                        antialiasing: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.padding.normal
                            spacing: Appearance.spacing.small

                            // Preview area
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: card.height - (Appearance.font.size.small * 2 + Appearance.spacing.normal * 2)

                                // Image preview for images
                                StyledClippingRect {
                                    id: imagePreview
                                    anchors.fill: parent
                                    radius: Appearance.rounding.small
                                    visible: cell.modelData.type === "image"

                                    CachingImage {
                                        id: image
                                        anchors.fill: parent
                                        path: cell.modelData.path || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    // fallback icon while image loads
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        visible: image.status !== Image.Ready
                                        text: "image"
                                        color: Colours.palette.m3onSurfaceVariant
                                    }
                                }

                                // Text preview for text items
                                StyledText {
                                    id: textPreview
                                    anchors.fill: parent
                                    visible: cell.modelData.type !== "image"
                                    text: cell.modelData.preview || (typeof cell.modelData.text === "string" ? cell.modelData.text.slice(0, 240) : "")
                                    font.pointSize: Appearance.font.size.small
                                    color: Colours.palette.m3onSurface
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 6
                                    horizontalAlignment: Text.AlignLeft
                                    verticalAlignment: Text.AlignTop
                                }

                                // Overlay actions (copy by clicking anywhere)
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Clipboard.copyEntry(cell.modelData)
                                }

                                MouseArea {
                                    id: hoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }
                            }

                            // footer row with icon, preview text and buttons
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.spacing.small

                                MaterialIcon {
                                    text: modelData.icon || (modelData.type === "image" ? "image" : "text_snippet")
                                    font.pointSize: Appearance.font.size.small * 1.1
                                    color: Colours.palette.m3primary
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.type === "image" ? qsTr("Image") : (modelData.preview || "")
                                    font.pointSize: Appearance.font.size.small
                                    color: Colours.palette.m3onSurfaceVariant
                                    elide: Text.ElideRight

                                    MouseArea {
                                        id: _mouseArea
                                        hoverEnabled: true
                                        anchors.fill: parent
                                    }
                                }

                                IconButton {
                                    icon: "push_pin"
                                    type: IconButton.Text
                                    checked: cell.pinned
                                    toggle: true
                                    activeColour: Colours.palette.m3primary
                                    onClicked: {
                                        cell.pinned = !cell.pinned;
                                        Clipboard.togglePin(cell.modelData.id);
                                    }
                                }

                                IconButton {
                                    icon: "content_copy"
                                    type: IconButton.Text
                                    onClicked: Clipboard.copyEntry(modelData)
                                }

                                IconButton {
                                    icon: "delete"
                                    type: IconButton.Text
                                    onClicked: Clipboard.removeEntry(modelData.id)
                                }
                            }
                        } // ColumnLayout
                    } // StyledRect
                } // delegate Item
            } // GridView
        } // StyledRect
    } // ColumnLayout

}
