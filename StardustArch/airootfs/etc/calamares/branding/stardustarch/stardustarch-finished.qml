import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import io.calamares.core 1.0
import io.calamares.ui 1.0

/*
 * StardustArch finished page.
 *
 * This file is loaded through finishedq's qmlSearch/qmlFilename override in
 * /etc/calamares/modules/finishedq.conf. It deliberately shows the
 * post-install warning unconditionally: the success/failure detail is in
 * /var/log/stardustarch-postinstall.log on the target.
 */
Page {
    id: root
    width: parent ? parent.width : 900
    height: parent ? parent.height : 620

    background: Item {
        Rectangle { anchors.fill: parent; color: "#0d1120" }
        Image {
            anchors.fill: parent
            source: "wallpaper.jpg"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.85
        }
        Rectangle { anchors.fill: parent; color: "#0d1120"; opacity: 0.32 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 36
        spacing: 18

        Image {
            source: "logo.png"
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            Layout.alignment: Qt.AlignHCenter
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }

        Label {
            text: qsTr("Installation complete")
            font.pixelSize: 28
            font.bold: true
            color: "#eef2ff"
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: qsTr("%1 has been installed on your computer.").arg(
                      Branding.string(Branding.ProductName))
            color: "#cbd3e8"
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: warningText.implicitHeight + 32
            radius: 8
            color: "#171f35"
            border.color: "#f0c674"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6

                Label {
                    text: qsTr("Before you reboot")
                    color: "#f0c674"
                    font.bold: true
                    font.pixelSize: 15
                }

                Label {
                    id: warningText
                    text: qsTr("The installer runs <b>pacman -Syu</b> in the target before finishing. " +
                               "If that step failed (for example because the network was unavailable), " +
                               "the installation is still usable: boot the new system, connect to the network, " +
                               "and run <b>sudo pacman -Syu</b> once. " +
                               "Details: <b>/var/log/stardustarch-postinstall.log</b>.")
                    textFormat: Text.RichText
                    color: "#eef2ff"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Label {
            text: qsTr("A full Calamares log is available in the Live user's home directory and is copied to /var/log/installation.log on the target.")
            color: "#8e99b8"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 10

            Button {
                text: qsTr("Close installer")
                icon.name: "application-exit"
                onClicked: ViewManager.quit()
            }

            Button {
                text: qsTr("Restart system")
                icon.name: "system-reboot"
                onClicked: config.doRestart(true)
            }
        }
    }

    function onActivate() {
    }

    function onLeave() {
    }
}
