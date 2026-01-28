pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

/* Clipboard service singleton
 *
 * Responsibilities:
 * - Poll the system clipboard periodically (uses wl-paste) and maintain a history of recent entries.
 * - Store entries as a ScriptModel available at `history`.
 * - Support basic text and image clipboard entries. Images are written to /tmp and the path is stored.
 * - Provide actions: copy an entry back to clipboard, toggle pin, remove entry, clear history, manualAdd.
 *
 * Notes:
 * - This implementation assumes `wl-paste`/`wl-copy` are available on the host.
 * - It uses `StdioCollector` (used elsewhere in project) to capture process stdout.
 */

Singleton {
    id: root

    // Configuration
    property int pollInterval: 1000           // ms between polls
    property int maxEntries: 50               // max entries kept
    property int previewLimit: 140            // preview text length
    property bool enabled: true

    // State
    property string lastText: ""
    readonly property var history: ScriptModel {
        values: []
    }

    // History version increments when clipboard history changes
    property int historyVersion: 0

    // Poll timer: periodically runs `wl-paste` to read text clipboard
    Timer {
        id: pollTimer
        interval: root.pollInterval
        repeat: true
        running: root.enabled
        onTriggered: {
            // Use --no-newline to avoid trailing newline artifacts
            pasteProc.command = ["sh", "-c", "wl-paste --no-newline 2>/dev/null || true"];
            pasteProc.running = true;
        }
    }

    // Process to get text clipboard contents
    Process {
        id: pasteProc

        // stdout collected into `text` by StdioCollector (project provides this)
        stdout: StdioCollector {
            onStreamFinished: {
                // text is available, handle content
                root._handlePaste(text);
            }
        }

        onExited: {
            // ensure subsequent runs work
            pasteProc.running = false;
        }
    }

    // Process used to capture image clipboard into a temporary PNG file
    Process {
        id: imgProc
        property string targetPath: ""

        onExited: {
            const path = imgProc.targetPath;
            if (exitCode === 0 && path) {
                const entry = {
                    id: `cb-${Date.now()}`,
                    type: "image",
                    path: path,
                    preview: "",
                    icon: "image",
                    time: Date.now(),
                    pinned: false
                };
                root._addEntry(entry);
            }
            imgProc.targetPath = "";
        }
    }

    // Internal helper: handle raw pasteProc output
    function _handlePaste(raw) {
        if (!raw)
            return;

        // If the output contains null bytes or binary-like signatures, try capturing an image
        // (sometimes wl-paste might return binary when image is on clipboard)
        if (raw.indexOf("\u0000") !== -1 || raw.indexOf("PNG") === 0 || raw.indexOf("JFIF") === 0 || raw.indexOf("GIF8") === 0) {
            _captureImageFromClipboard();
            return;
        }

        const text = String(raw).trim();
        if (text.length === 0)
            return;

        // Skip consecutive duplicates
        if (text === root.lastText)
            return;
        root.lastText = text;

        const entry = {
            id: `cb-${Date.now()}`,
            type: "text",
            text: text,
            preview: _makePreview(text),
            icon: _detectIcon(text),
            time: Date.now(),
            pinned: false
        };

        _addEntry(entry);
    }

    // Try to write an image from the clipboard to a temp file
    function _captureImageFromClipboard() {
        const path = `/tmp/caelestia-clipboard-${Date.now()}.png`;
        // `wl-paste --type image/png` writes raw png bytes; redirect to file
        imgProc.command = ["sh", "-c", `wl-paste --type image/png --no-newline > "${path}"`];
        imgProc.targetPath = path;
        imgProc.running = true;
    }

    // Generate a one-line preview for text entries
    function _makePreview(text) {
        if (!text)
            return "";
        let p = text.replace(/\s+/g, " ").trim();
        if (p.length > root.previewLimit)
            return p.slice(0, root.previewLimit) + "…";
        return p;
    }

    // Rudimentary icon detection for different text types
    function _detectIcon(text) {
        if (/^https?:\/\//i.test(text))
            return "link";
        if (/^mailto:/i.test(text) || /@.+\..+/.test(text))
            return "alternate_email";
        if (/^\d{3,}-\d{3,}/.test(text))
            return "phone";
        return "text_snippet";
    }

    // Add or move an entry into the history model
    function _addEntry(entry) {
        if (!entry)
            return;

        const arr = root.history.values.slice();

        // If identical entry exists (same text or same image path), move it to top instead of duplicating
        const idx = arr.findIndex(e => (e.type === entry.type) && (entry.type === "text" ? e.text === entry.text : e.path === entry.path));
        if (idx >= 0) {
            // update time and move to top
            const existing = arr.splice(idx, 1)[0];
            existing.time = Date.now();
            arr.unshift(existing);
        } else {
            arr.unshift(entry);
        }

        // Keep pinned items at the front, then by time
        arr.sort(function (a, b) {
            if (!!a.pinned !== !!b.pinned)
                return b.pinned ? 1 : -1;
            return b.time - a.time;
        });

        root.history.values = arr.slice(0, root.maxEntries);
        root.historyVersion = root.historyVersion + 1;
    }

    // Public: copy entry content back into system clipboard
    function copyEntry(entry) {
        if (!entry)
            return;
        if (entry.type === "text") {
            Quickshell.clipboardText = entry.text;
            if (typeof Toaster !== "undefined")
                Toaster.toast(qsTr("Copied to clipboard"), entry.preview || qsTr("Text copied"), "content_copy", Toast.Info);
        } else if (entry.type === "image" && entry.path) {
            // Use wl-copy to restore the image
            Quickshell.execDetached(["sh", "-c", `wl-copy --type image/png < "${entry.path}"`]);
            if (typeof Toaster !== "undefined")
                Toaster.toast(qsTr("Copied to clipboard"), qsTr("Image copied"), "image", Toast.Info);
        }
    }

    // Public: toggle pinned state for an entry
    function togglePin(id) {
        if (!id)
            return;
        const arr = root.history.values.slice();
        const idx = arr.findIndex(e => e.id === id);
        if (idx === -1)
            return;
        arr[idx].pinned = !arr[idx].pinned;
        // reorder with pinned first
        arr.sort(function (a, b) {
            if (!!a.pinned !== !!b.pinned)
                return b.pinned ? 1 : -1;
            return b.time - a.time;
        });
        root.history.values = arr;
        root.historyVersion = root.historyVersion + 1;
    }

    // Public: remove a specific entry by id
    function removeEntry(id) {
        if (!id)
            return;
        root.history.values = root.history.values.filter(function (e) {
            return e.id !== id;
        });
        root.historyVersion = root.historyVersion + 1;
    }

    // Public: clear history; by default preserve pinned items
    function clearHistory(preservePinned) {
        if (preservePinned === undefined)
            preservePinned = true;
        if (preservePinned)
            root.history.values = root.history.values.filter(e => !!e.pinned);
        else
            root.history.values = [];
        root.historyVersion = root.historyVersion + 1;
    }

    // Public: force-add arbitrary text (useful for testing or UI)
    function manualAdd(text) {
        if (!text || typeof text !== "string")
            return;
        const entry = {
            id: `cb-${Date.now()}`,
            type: "text",
            text: text,
            preview: _makePreview(text),
            icon: _detectIcon(text),
            time: Date.now(),
            pinned: false
        };
        _addEntry(entry);
    }

    Component.onCompleted: {
        pollTimer.start();
    }
}
