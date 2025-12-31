// Created by SemperDownload at Github
// Based on the Earlier 'Time Signature Copy Paste' plugin by @TeeDeeY at Github, which
// had stopped working for me in the latest Musescore Studio 4.xx versions. 
// Started as a simple update, but ended up adding quite a few features, most notably
// the ability to save and recall multiple time signature sequences and
// preserving custom additive numerators (i.e. 3+2/8 doesn't just paste as 5/8, as in earlier versions). 
//Still, it is all built directly on TeeDeeY's code, to whom foundational credit belongs for their
// tremendously useful plugin.
//
// Features included:
// - Refresh/Collect selection while dialog open
// - Per-score multi-preset save/load stored in score metaTag (saved with the score file)
// - Preserve numeratorString/denominatorString/groups for additive meters like 2+3/8
// - Clipboard save/load using JSON (still loads legacy semicolon format)

import MuseScore 3.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

MuseScore {
    menuPath: "Plugins.timesigCP_Semper"

    title: "Time Sig Copy-Paste v1.0 (Semper)"
    description: "An update to TeeDeeY's plugin, improving Musescore 4.xx compatibility and adding save/recall of time-sig sequences + additive numerator preservatio (meters of 2+3, etc.)"
    version: "1.0"
    pluginType: "dialog"

    requiresScore: true
    id: plugin

    property int margin: 10
    property string statusText: " "

    // Forced readable palette (simple + safe)
    property color uiBg: "#ffffff"
    property color uiPanel: "#f2f2f2"
    property color uiBorder: "#cfcfcf"
    property color uiText: "#000000"
    property color uiToolbar: "#e6e6e6"

    // Buffer arrays (assigned in one shot to trigger QML bindings)
    property var tsarrayN: []
    property var tsarrayD: []
    property var marrayN: []
    property var marrayD: []

    // Preserve explicit display strings + beaming groupings
    property var tsNumStr: []
    property var tsDenStr: []
    property var tsGroups: []

    // Presets stored in the score itself
    property string presetMetaTagKey: "TimeSigCP_BufferPresets_v1"
    property var scorePresets: [] // [{name, tsN, tsD, mN, mD, numStr, denStr, groups}...]

    // Hidden clipboard helper
    TextEdit {
        id: cP
        visible: false
        text: ""
    }

    ListModel { id: presetModel }

    function clearArrays() {
        tsarrayN = []
        tsarrayD = []
        marrayN = []
        marrayD = []
        tsNumStr = []
        tsDenStr = []
        tsGroups = []
    }

    function toPlainArray(v) {
        if (v === undefined || v === null) return null
        var t = typeof v
        if (t === "string" || t === "number" || t === "boolean") return v
        if (v.length !== undefined) {
            var arr = []
            for (var i = 0; i < v.length; i++)
                arr.push(v[i])
            return arr
        }
        return v
    }

    function groupsEqual(a, b) {
        if (a === undefined || a === null || a === "") a = null
        if (b === undefined || b === null || b === "") b = null
        if (a === null && b === null) return true

        var ta = typeof a
        var tb = typeof b
        if (ta !== tb)
            return ("" + a) === ("" + b)

        if (ta === "string" || ta === "number" || ta === "boolean")
            return a === b

        if (a.length !== undefined && b.length !== undefined) {
            if (a.length !== b.length) return false
            for (var i = 0; i < a.length; i++) {
                if (a[i] !== b[i]) return false
            }
            return true
        }

        return JSON.stringify(a) === JSON.stringify(b)
    }

    function displayForMeasure(i) {
        var ns = plugin.tsNumStr[i]
        var ds = plugin.tsDenStr[i]
        if (ns !== undefined && ns !== null && ns !== "" && ds !== undefined && ds !== null && ds !== "")
            return ns + "/" + ds
        return plugin.tsarrayN[i] + "/" + plugin.tsarrayD[i]
    }

    function buildDefaultPresetName() {
        if (plugin.tsarrayN.length < 1) return ""
        var parts = []
        var out = ""
        for (var i = 0; i < plugin.tsarrayN.length; i++) {
            parts.push(displayForMeasure(i))
            out = parts.join(" _ ")
            if (out.length > 90) {
                parts.push("...")
                out = parts.join(" _ ")
                break
            }
        }
        return out
    }

    function refreshPresetModel() {
        presetModel.clear()
        for (var i = 0; i < scorePresets.length; i++) {
            presetModel.append({ text: scorePresets[i].name, idx: i })
        }
        if (presetCombo.currentIndex >= presetModel.count)
            presetCombo.currentIndex = presetModel.count - 1
        if (presetCombo.currentIndex < 0)
            presetCombo.currentIndex = 0
    }

    function loadPresetsFromScore() {
        scorePresets = []
        if (!curScore) return

        var raw = curScore.metaTag(presetMetaTagKey)
        if (!raw || raw.trim() === "")
            return

        try {
            var obj = JSON.parse(raw)
            if (!obj || !obj.presets || obj.presets.length === undefined)
                return
            scorePresets = obj.presets
        } catch (e) {
            // ignore parse errors
        }
    }

    function savePresetsToScore() {
        if (!curScore) return
        var obj = { version: 1, presets: scorePresets }
        var raw = JSON.stringify(obj)

        curScore.startCmd()
        curScore.setMetaTag(presetMetaTagKey, raw)
        curScore.endCmd()
    }

    function addOrReplacePreset(name) {
        if (!name) return false
        if (plugin.tsarrayN.length < 1) return false

        var preset = {
            name: name,
            tsN: plugin.tsarrayN.slice(0),
            tsD: plugin.tsarrayD.slice(0),
            mN: plugin.marrayN.slice(0),
            mD: plugin.marrayD.slice(0),
            numStr: plugin.tsNumStr.slice(0),
            denStr: plugin.tsDenStr.slice(0),
            groups: plugin.tsGroups.slice(0)
        }

        for (var i = 0; i < scorePresets.length; i++) {
            if (scorePresets[i].name === name) {
                scorePresets[i] = preset
                savePresetsToScore()
                refreshPresetModel()
                return true
            }
        }

        scorePresets.push(preset)
        savePresetsToScore()
        refreshPresetModel()
        return true
    }

    function loadPresetIntoBuffer(preset) {
        if (!preset) return false

        plugin.tsarrayN = (preset.tsN || []).slice(0)
        plugin.tsarrayD = (preset.tsD || []).slice(0)
        plugin.marrayN  = (preset.mN  || []).slice(0)
        plugin.marrayD  = (preset.mD  || []).slice(0)
        plugin.tsNumStr = (preset.numStr || []).slice(0)
        plugin.tsDenStr = (preset.denStr || []).slice(0)
        plugin.tsGroups = (preset.groups || []).slice(0)

        saveTS.visible = (plugin.tsarrayN.length > 0)
        goPaste.visible = (plugin.tsarrayN.length > 0)

        if (presetNameInput)
            presetNameInput.text = preset.name

        return (plugin.tsarrayN.length > 0)
    }

    function deletePresetByIndex(idx) {
        if (idx < 0 || idx >= scorePresets.length) return false
        scorePresets.splice(idx, 1)
        savePresetsToScore()
        refreshPresetModel()
        return true
    }

    function findTimeSigElementInMeasure(measure, staffIdx) {
        if (!measure) return null
        var seg = measure.firstSegment
        var track = staffIdx * 4 // voice 0
        var guard = 0

        while (seg && guard < 5000) {
            guard++

            var el = seg.elementAt(track)
            if (el && el.type === Element.TIMESIG)
                return el

            if (seg.annotations && seg.annotations.length !== undefined) {
                for (var i = 0; i < seg.annotations.length; i++) {
                    var a = seg.annotations[i]
                    if (a && a.type === Element.TIMESIG)
                        return a
                }
            }

            seg = seg.nextInMeasure
        }
        return null
    }

    // FIXED: Build arrays locally, assign once (so QML updates bindings)
    function copyselected() {
        if (!curScore) {
            statusText = "Open a score first."
            saveTS.visible = false
            goPaste.visible = false
            return
        }

        var cursor = curScore.newCursor()

        cursor.rewind(1)
        if (!cursor.segment) {
            statusText = "No range selection found. Select measures and click Refresh/Collect."
            saveTS.visible = (plugin.tsarrayN.length > 0)
            goPaste.visible = (plugin.tsarrayN.length > 0)
            return
        }

        var startTick = cursor.tick

        cursor.rewind(2)
        var endTick = cursor.tick
        if (endTick === 0 || endTick <= startTick)
            endTick = curScore.lastSegment.tick + 1

        // Local arrays (so we can assign once)
        var tN = []
        var tD = []
        var aN = []
        var aD = []
        var nS = []
        var dS = []
        var gS = []

        cursor.rewind(1)
        cursor.voice = 0
        cursor.staffIdx = 0

        var lastNumStr = ""
        var lastDenStr = ""
        var lastGroups = null

        while (cursor.segment && (cursor.tick < endTick)) {
            var nom = cursor.measure.timesigNominal
            var act = cursor.measure.timesigActual

            tN.push(parseInt(nom.numerator, 10))
            tD.push(parseInt(nom.denominator, 10))
            aN.push(parseInt(act.numerator, 10))
            aD.push(parseInt(act.denominator, 10))

            var tsEl = findTimeSigElementInMeasure(cursor.measure, 0)
            if (tsEl) {
                lastNumStr = (tsEl.numeratorString !== undefined && tsEl.numeratorString !== null) ? ("" + tsEl.numeratorString) : ""
                lastDenStr = (tsEl.denominatorString !== undefined && tsEl.denominatorString !== null) ? ("" + tsEl.denominatorString) : ""
                lastGroups = toPlainArray(tsEl.groups)
            }

            nS.push(lastNumStr)
            dS.push(lastDenStr)
            gS.push(lastGroups)

            cursor.nextMeasure()
        }

        // Assign once -> bindings update
        plugin.tsarrayN = tN
        plugin.tsarrayD = tD
        plugin.marrayN  = aN
        plugin.marrayD  = aD
        plugin.tsNumStr = nS
        plugin.tsDenStr = dS
        plugin.tsGroups = gS

        saveTS.visible = true
        goPaste.visible = true

        if (presetNameInput)
            presetNameInput.text = buildDefaultPresetName()

        statusText = "Collected " + plugin.tsarrayN.length + " measures for Paste!"
    }

    // TO DO: Still havent fixed issue of pasting past end of score.
    // Run paste on the next tick of the UI loop so the dialog never "greys" while work starts
    
    // Insert a measure ONLY if we actually need to move past the end of the score.
    // This prevents trailing blank measures when the score already has enough measures.
    function ensureNextMeasure(cursor) {
        // Advance to the next measure; if we're at the end, insert exactly ONE measure and advance into it.
        // MuseScore's cursor sometimes doesn't "see" the newly inserted measure immediately, so we retry
        // and fall back to a fresh cursor to discover the correct tick.
        var t = cursor.tick

        if (cursor.nextMeasure())
            return true

        cmd("insert-measure")

        // First retry on the same cursor after rewinding.
        cursor.rewindToTick(t)
        if (cursor.nextMeasure())
            return true

        // Fallback: use a fresh cursor to locate the next-measure tick, then rewind the original cursor there.
        var c2 = curScore.newCursor()
        c2.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE
        c2.voice = cursor.voice
        c2.staffIdx = cursor.staffIdx
        c2.rewindToTick(t)

        if (c2.nextMeasure()) {
            cursor.rewindToTick(c2.tick)
            return true
        }

        return false
    }

function runPasteNonBlocking() {
        statusText = "Pasting..."
        Qt.callLater(function() {
            try {
                go()
            } catch (e) {
                statusText = "Error during paste: " + e
            }
        })
    }

    function go() {
        if (!curScore) {
            statusText = "Open a score first."
            return
        }
        if (plugin.tsarrayN.length < 1) {
            statusText = "Nothing to paste. Select a range and Refresh/Collect, or Load a preset first."
            return
        }

        // Safety guard: prevent crashes if clipboard parsing produced invalid data.
        for (var i = 0; i < plugin.tsarrayN.length; i++) {
            var n = plugin.tsarrayN[i]
            var d = plugin.tsarrayD[i]
            var an = plugin.marrayN[i]
            var ad = plugin.marrayD[i]

            if (isNaN(n) || isNaN(d) || n < 1 || d < 1 || isNaN(an) || isNaN(ad) || an < 1 || ad < 1) {
                statusText = "Buffer is invalid (non-numeric time signature). Reload buffer or Refresh/Collect."
                return
            }

            // groups must never be null (safe default)
            if (plugin.tsGroups && (plugin.tsGroups[i] === null || plugin.tsGroups[i] === undefined))
                plugin.tsGroups[i] = []
        }

        var cursor = curScore.newCursor()
        cursor.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE

        var loop = parseInt(inputtext.text, 10)
        if (isNaN(loop) || loop < 1 || loop > 2000)
            loop = 1

        cursor.voice = 0
        cursor.staffIdx = 0

        cursor.rewind(1)
        if (!cursor.segment) {
            statusText = "Click a destination point in the score, then press Go! Paste."
            return
        }

        var ct = cursor.tick
        var tl = plugin.tsarrayN.length

        // Only insert measures if we *need* them.
        // Needed measures = (tl * loop). If there are already enough measures remaining in the score
        // from the destination measure onward, insert 0.
        var neededMeasures = tl * loop
        if (neededMeasures < 1) neededMeasures = 1

        var probe = curScore.newCursor()
        probe.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE
        probe.voice = 0
        probe.staffIdx = 0
        probe.rewindToTick(ct)

        var availableMeasures = 1 // current destination measure counts
        var guard = 0
        while (probe.nextMeasure() && guard < 200000) {
            availableMeasures++
            guard++
        }

        var missing = neededMeasures - availableMeasures
        if (missing < 0) missing = 0

        for (var mi = 0; mi < missing; mi++)
            cmd("insert-measure")

        // Recreate cursor after inserting measures (prevents stale cursor issues).
        cursor = curScore.newCursor()
        cursor.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE
        cursor.voice = 0
        cursor.staffIdx = 0
        cursor.rewindToTick(ct)
        if (!cursor.segment && ct > 0)
            cursor.rewindToTick(ct - 1)
        var ts1 = newElement(Element.TIMESIG)
        ts1.timesig = cursor.measure.timesigNominal
        curScore.startCmd()
        cursor.add(ts1)
        curScore.endCmd()

        cursor.rewindToTick(ct)

        var prevN = null
        var prevD = null
        var prevNumStr = null
        var prevDenStr = null
        var prevGroups = null

        for (var rep = 0; rep < loop; rep++) {
            var ctick = cursor.tick

            for (var k = 0; k < tl; k++) {
                var curN = plugin.tsarrayN[k]
                var curD = plugin.tsarrayD[k]
                var curNumStr = (plugin.tsNumStr[k] !== undefined && plugin.tsNumStr[k] !== null) ? ("" + plugin.tsNumStr[k]) : ""
                var curDenStr = (plugin.tsDenStr[k] !== undefined && plugin.tsDenStr[k] !== null) ? ("" + plugin.tsDenStr[k]) : ""
                var curGroups = (plugin.tsGroups[k] !== undefined) ? plugin.tsGroups[k] : null

                var sameAsPrev =
                        (prevN !== null) &&
                        (curN === prevN) &&
                        (curD === prevD) &&
                        (curNumStr === prevNumStr) &&
                        (curDenStr === prevDenStr) &&
                        groupsEqual(curGroups, prevGroups)

                if (sameAsPrev) {
                    // Advance unless this is the very last measure of the very last repetition.
                    if ((rep < loop - 1) || (k < tl - 1)) {
                        if (!cursor.nextMeasure()) {
                            statusText = "Error: not enough measures inserted (hit end of score)."
                            return
                        }
                    }
                } else {
                    var ts = newElement(Element.TIMESIG)
                    ts.timesig = fraction(curN, curD)

                    if (curNumStr !== "")
                        ts.numeratorString = curNumStr
                    if (curDenStr !== "")
                        ts.denominatorString = curDenStr
                    if (curGroups !== null && curGroups !== undefined && curGroups !== "")
                        ts.groups = curGroups

                    var ct3 = cursor.tick
                    curScore.startCmd()
                    cursor.add(ts)
                    curScore.endCmd()

                    prevN = curN
                    prevD = curD
                    prevNumStr = curNumStr
                    prevDenStr = curDenStr
                    prevGroups = curGroups

                    cursor.rewindToTick(ct3)

                    // Advance unless this is the very last measure of the very last repetition.
                    if ((rep < loop - 1) || (k < tl - 1)) {
                        if (!cursor.nextMeasure()) {
                            statusText = "Error: not enough measures inserted (hit end of score)."
                            return
                        }
                    }
                }
            }

            cursor.rewindToTick(ctick)
            for (var a = 0; a < tl; a++) {
                curScore.startCmd()
                cursor.measure.timesigActual = fraction(plugin.marrayN[a], plugin.marrayD[a])
                curScore.endCmd()

                // Advance unless this is the very last measure of the very last repetition.
                if ((rep < loop - 1) || (a < tl - 1)) {
                    if (!cursor.nextMeasure()) {
                        statusText = "Error: not enough measures inserted (hit end of score)."
                        return
                    }
                }
            }
        }

        statusText = "Done."
    }

    function saveBufferToClipboard() {
        if (plugin.tsarrayN.length < 1) {
            statusText = "Nothing to save."
            return
        }

        var measures = []
        for (var i = 0; i < plugin.tsarrayN.length; i++) {
            measures.push({
                n: plugin.tsarrayN[i],
                d: plugin.tsarrayD[i],
                an: plugin.marrayN[i],
                ad: plugin.marrayD[i],
                numStr: (plugin.tsNumStr[i] !== undefined && plugin.tsNumStr[i] !== null) ? ("" + plugin.tsNumStr[i]) : "",
                denStr: (plugin.tsDenStr[i] !== undefined && plugin.tsDenStr[i] !== null) ? ("" + plugin.tsDenStr[i]) : "",
                groups: (plugin.tsGroups[i] !== undefined) ? plugin.tsGroups[i] : null
            })
        }

        var obj = { type: "TimeSigCP", version: 2, measures: measures }
        var outstr = JSON.stringify(obj)

        cP.text = outstr
        cP.selectAll()
        cP.copy()

        statusText = "Saved to clipboard (" + plugin.tsarrayN.length + " measures)."
    }

    // Loads JSON v2 or legacy semicolon format
    function loadBufferFromClipboard() {
        cP.text = ""
        cP.selectAll()
        cP.paste()

        var testr = cP.text
        if (!testr || testr.trim() === "") {
            statusText = "Clipboard is empty."
            return
        }

        // Validate + normalize a candidate buffer WITHOUT mutating the current buffer unless it is valid.
        function normalizeAndValidate(tN, tD, aN, aD, nS, dS, gS) {
            if (!tN || !tD || tN.length < 1 || tN.length !== tD.length)
                return "Invalid buffer length."

            // normalize actual arrays to match length
            if (!aN || aN.length !== tN.length) aN = tN.slice(0)
            if (!aD || aD.length !== tD.length) aD = tD.slice(0)

            if (!nS) nS = []
            if (!dS) dS = []
            if (!gS) gS = []

            while (nS.length < tN.length) nS.push("")
            while (dS.length < tN.length) dS.push("")
            while (gS.length < tN.length) gS.push([])

            for (var i = 0; i < tN.length; i++) {
                var n = tN[i], d = tD[i], an = aN[i], ad = aD[i]

                if (isNaN(n) || isNaN(d) || n < 1 || d < 1)
                    return "Invalid nominal time signature at index " + i + "."

                if (isNaN(an) || isNaN(ad) || an < 1 || ad < 1) {
                    // If actual is missing/bad, fall back to nominal (prevents NaN buffer / crashes)
                    aN[i] = n
                    aD[i] = d
                }

                if (nS[i] === undefined || nS[i] === null) nS[i] = ""
                if (dS[i] === undefined || dS[i] === null) dS[i] = ""

                // groups must be an array; null/undefined becomes [] (safe default)
                if (gS[i] === null || gS[i] === undefined) gS[i] = []
                if (gS[i].length !== undefined && typeof gS[i] !== "string") {
                    // ok: looks array-like
                } else {
                    return "Invalid grouping data at index " + i + "."
                }
            }

            return { tN: tN, tD: tD, aN: aN, aD: aD, nS: nS, dS: dS, gS: gS }
        }

        // JSON (preferred; preserves grouping)
        try {
            var obj = JSON.parse(testr)
            if (obj && obj.type === "TimeSigCP" && obj.measures && obj.measures.length !== undefined) {
                var tN = [], tD = [], aN = [], aD = [], nS = [], dS = [], gS = []
                for (var i = 0; i < obj.measures.length; i++) {
                    var m = obj.measures[i]
                    tN.push(parseInt(m.n, 10))
                    tD.push(parseInt(m.d, 10))
                    aN.push(parseInt(m.an, 10))
                    aD.push(parseInt(m.ad, 10))
                    nS.push((m.numStr !== undefined && m.numStr !== null) ? ("" + m.numStr) : "")
                    dS.push((m.denStr !== undefined && m.denStr !== null) ? ("" + m.denStr) : "")
                    // null/undefined groups will be normalized to [] below
                    gS.push((m.groups !== undefined) ? m.groups : null)
                }

                var norm = normalizeAndValidate(tN, tD, aN, aD, nS, dS, gS)
                if (typeof norm === "string") {
                    statusText = "Error: Clipboard JSON is not valid TimeSigCP data. (" + norm + ")"
                    return
                }

                plugin.tsarrayN = norm.tN
                plugin.tsarrayD = norm.tD
                plugin.marrayN  = norm.aN
                plugin.marrayD  = norm.aD
                plugin.tsNumStr = norm.nS
                plugin.tsDenStr = norm.dS
                plugin.tsGroups = norm.gS

                saveTS.visible = true
                goPaste.visible = true
                if (presetNameInput)
                    presetNameInput.text = buildDefaultPresetName()

                statusText = "Loaded " + plugin.tsarrayN.length + " measures from clipboard (JSON)."
                return
            }
        } catch (e) {
            // fall through to legacy
        }

        // Legacy semicolon (no grouping). Must be strictly parseable or we refuse to load.
        if (testr.indexOf(";") < 0) {
            statusText = "Error: No valid TimeSigCP JSON found in clipboard."
            return
        }

        var tot1 = 0
        var str = ""
        while (tot1 < testr.length && testr[tot1] !== ";") {
            str += testr[tot1]
            tot1++
        }

        if (!str || !/^[0-9]+$/.test(str.trim())) {
            statusText = "Error: Clipboard data is not valid TimeSigCP JSON (or legacy format)."
            return
        }

        var total = parseInt(str, 10)
        if (isNaN(total) || total < 1) {
            statusText = "Error: Could not parse clipboard data."
            return
        }
        tot1++ // skip ';'

        var tN2 = [], tD2 = [], aN2 = [], aD2 = [], nS2 = [], dS2 = [], gS2 = []

        function readField() {
            var s = ""
            while (tot1 < testr.length && testr[tot1] !== ";") {
                s += testr[tot1]
                tot1++
            }
            // skip ';' if present
            if (tot1 < testr.length && testr[tot1] === ";")
                tot1++
            return parseInt(s, 10)
        }

        for (var l1 = 0; l1 < total; l1++) {
            var n = readField()
            var d = readField()
            var an = readField()
            var ad = readField()

            if (isNaN(n) || isNaN(d) || n < 1 || d < 1) {
                statusText = "Error: Clipboard legacy data malformed (non-numeric time signature)."
                return
            }

            // If legacy doesn't contain valid actuals, fall back safely.
            if (isNaN(an) || isNaN(ad) || an < 1 || ad < 1) {
                an = n
                ad = d
            }

            tN2.push(n)
            tD2.push(d)
            aN2.push(an)
            aD2.push(ad)
            nS2.push("")
            dS2.push("")
            gS2.push([]) // NEVER null (prevents paste crash)
        }

        plugin.tsarrayN = tN2
        plugin.tsarrayD = tD2
        plugin.marrayN  = aN2
        plugin.marrayD  = aD2
        plugin.tsNumStr = nS2
        plugin.tsDenStr = dS2
        plugin.tsGroups = gS2

        saveTS.visible = true
        goPaste.visible = true
        if (presetNameInput)
            presetNameInput.text = buildDefaultPresetName()

        statusText = "Loaded " + plugin.tsarrayN.length + " measures from clipboard (legacy; no grouping)."
    }
    onRun: {
        statusText = " "
        saveTS.visible = false
        goPaste.visible = false

        loadPresetsFromScore()
        refreshPresetModel()

        plugindialog.open()
        Qt.callLater(copyselected)
    }

    Dialog {
        id: plugindialog
        modal: false
        width: 560
        height: 420

        // keep footer always visible
        footer: DialogButtonBox {
            background: Rectangle { color: uiPanel; border.color: uiBorder }

            Button {
                id: goPaste
                text: "Go! Paste"
                visible: false
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                onClicked: runPasteNonBlocking()
            }


        }

        // IMPORTANT FIX: remove anchors.fill so content does not extend under footer
        contentItem: ColumnLayout {
            spacing: 0

            ToolBar {
                Layout.fillWidth: true
                background: Rectangle { color: uiToolbar; border.color: uiBorder }
                RowLayout {
                    anchors.fill: parent
                    Label {
                        Layout.fillWidth: true
                        text: "  "
                        color: uiText
                        elide: Label.ElideRight
                    }
                }
            }

            ScrollView {
                id: scrollView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Ensure the light background actually paints behind the top text even in dark mode.
                // (Rectangle does not auto-size to its children unless we bind implicitHeight.)
                Rectangle {
                    id: scrollBg
                    color: uiBg
                    width: scrollView.availableWidth > 0 ? scrollView.availableWidth : scrollView.width
                    implicitHeight: contentCol.implicitHeight + (margin * 2)

                    ColumnLayout {
                        id: contentCol
                        width: parent.width
                        anchors.margins: margin
                        spacing: 10

                        Text {
                            color: uiText
                            text: 
                                  "Workflow:\n" +
                                  "1) Select measures        2) Click 'Refresh/Collect Selection' with each new selection; \n" +
                                  "3) (Optional) Save preset;         4) Click destination; \n" +
                                  "5) Click Go! Paste (only visible when measures are loaded in buffer).\n \n" +
                                  "Note: Scroll down for instructions on copying between 2 scores"
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            color: "red"
                            text: plugin.statusText
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            spacing: 10
                            Text { text: "REPEAT paste how many times?"; color: uiText }

                            // Editable numeric field (defaults to 1). Clamped to 1..2000.
                            TextField {
                                id: inputtext
                                text: "1"
                                width: 80
                                selectByMouse: true
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 1; top: 2000 }

                                // Force readable field styling regardless of MuseScore theme
                                color: uiText
                                background: Rectangle {
                                    color: "#ffffff"
                                    border.color: uiBorder
                                    radius: 3
                                }

                                onEditingFinished: {
                                    var v = parseInt(text, 10)
                                    if (isNaN(v) || v < 1) v = 1
                                    if (v > 2000) v = 2000
                                    text = "" + v
                                }
                            }
                        }

                        GroupBox {
                            title: "Selection / Buffer"
                            Layout.fillWidth: true
                            background: Rectangle { color: uiPanel; border.color: uiBorder; radius: 4 }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    spacing: 10
                                    Button {
                                        text: "Refresh / Collect Selection"
                                        onClicked: copyselected()
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        color: uiText
                                        wrapMode: Text.WordWrap
                                        text: (plugin.tsarrayN.length > 0)
                                              ? ("Buffered measures: " + plugin.tsarrayN.length)
                                              : "Buffered measures: (none)"
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "Presets (saved in this score)"
                            Layout.fillWidth: true
                            background: Rectangle { color: uiPanel; border.color: uiBorder; radius: 4 }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    spacing: 10
                                    Text { text: "Preset:"; color: uiText }
                                    ComboBox {
                                        id: presetCombo
                                        Layout.fillWidth: true
                                        model: presetModel
                                        textRole: "text"
                                        enabled: (presetModel.count > 0)
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Text { text: "Name:"; color: uiText }
                                    // KEEP TextInput simple for compatibility
                                    TextInput {
                                        id: presetNameInput
                                        Layout.fillWidth: true
                                        text: ""
                                        color: uiText
                                    }
                                }

                                RowLayout {
                                    spacing: 10
                                    Button {
                                        text: "Save Buffer as Preset"
                                        enabled: (plugin.tsarrayN.length > 0)
                                        onClicked: {
                                            var nm = presetNameInput.text.trim()
                                            if (nm === "")
                                                nm = buildDefaultPresetName()
                                            if (nm === "") {
                                                statusText = "Give the preset a name (or select a range to auto-name)."
                                                return
                                            }
                                            if (addOrReplacePreset(nm)) {
                                                statusText = "Preset saved in score: " + nm + " (remember to SAVE the score file)."
                                            } else {
                                                statusText = "Could not save preset."
                                            }
                                        }
                                    }

                                    Button {
                                        text: "Load Preset into Buffer"
                                        enabled: (presetModel.count > 0)
                                        onClicked: {
                                            if (presetModel.count < 1) return
                                            var idx = presetModel.get(presetCombo.currentIndex).idx
                                            var ok = loadPresetIntoBuffer(scorePresets[idx])
                                            statusText = ok ? ("Loaded preset: " + scorePresets[idx].name) : "Failed to load preset."
                                        }
                                    }

                                    Button {
                                        text: "Delete Preset"
                                        enabled: (presetModel.count > 0)
                                        onClicked: {
                                            if (presetModel.count < 1) return
                                            var idx = presetModel.get(presetCombo.currentIndex).idx
                                            var nm = scorePresets[idx].name
                                            if (deletePresetByIndex(idx))
                                                statusText = "Deleted preset: " + nm + " (remember to SAVE the score file)."
                                            else
                                                statusText = "Failed to delete preset."
                                        }
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "Clipboard Save/Load (portable)"
                            Layout.fillWidth: true
                            background: Rectangle { color: uiPanel; border.color: uiBorder; radius: 4 }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    spacing: 10
                                    Button {
                                        id: saveTS
                                        text: "Save Buffer to Clipboard"
                                        visible: false
                                        enabled: (plugin.tsarrayN.length > 0)
                                        onClicked: saveBufferToClipboard()
                                    }
                                    Button {
                                        id: loadTS
                                        text: "Load Buffer from Clipboard"
                                        onClicked: loadBufferFromClipboard()
                                    }
                                }

                                Text {
                                    color: uiText
                                    text: "Clipboard mode is for moving a time-sig sequence between scores. \n" +
                                    "‘Save’ copies a JSON string to your system clipboard;\n" + 
                                    "‘Load’ reads JSON from your clipboard.\n" +
                                    "('Save' is only visible if Buffer is refreshed/collected)"
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // bigger spacer so last controls never sit behind footer on some themes
                        Item { height: 60 }
                    }
                }
            }
        }
    }
}
