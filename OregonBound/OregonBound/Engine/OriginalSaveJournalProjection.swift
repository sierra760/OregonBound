import Foundation

extension OriginalSaveJournal {
    struct ProjectedRow: Equatable, Sendable {
        let recordIndex: Int
        let record: Record
        /// Most recent date record, including a hidden heading. Nil before first date.
        let date: DateMarker?
        let isVisible: Bool
        let isBold: Bool
        let presentation: Presentation
        /// QuickDraw wrapped line indices, not record ordinals. Nil after any gap.
        let firstLine: Int?
        let lineCount: Int?
    }
    struct SparseIndexEntry: Equatable, Sendable {
        let recordIndex: Int
        let byteOffset: Int
        let firstLine: Int?
    }
    struct Projection: Equatable, Sendable {
        /// Includes hidden/unresolved records with their unchanged source bytes.
        let rows: [ProjectedRow]
        let sparseIndex: [SparseIndexEntry]
        let totalLineCount: Int?
        var visibleRows: [ProjectedRow] { rows.filter(\.isVisible) }
        var unresolvedVisibleRows: [ProjectedRow] { rows.filter { $0.isVisible && $0.presentation.text == nil } }
    }

    /// CODE14:1904–1ae6. The original predicate returns1 for hidden, not visible.
    /// Dates look forward only as far as the next date record or used-buffer end.
    func visibility(localWagonSlot local: Int) -> [Bool] {
        precondition((0..<32).contains(local))
        var result = Array(repeating: false, count: records.count)
        var visibleUntilNextDate = false
        for index in records.indices.reversed() {
            let record = records[index], opcode = Int(record.opcode)
            if opcode == 120 {
                result[index] = visibleUntilNextDate
                visibleUntilNextDate = false
                continue
            }
            let visible: Bool
            if ((63...69).contains(opcode) && opcode != 65) || [20,25,36,43,105].contains(opcode) {
                visible = record.wagonSlotBits == local
            } else if (106...109).contains(opcode) && record.parameterByte == 130 {
                visible = Int(record.rawBytes[2] & 31) == local
            } else if (70...84).contains(opcode) {
                // Perspective tests use the complete bytes, not packed actor masks.
                let participant = Int(record.rawBytes[1]) == local || Int(record.rawBytes[2]) == local
                visible = opcode == 71 || opcode == 72 || (opcode == 80 ? !participant : participant)
            } else if opcode == 118 {
                visible = record.wagonSlotBits == local || record.speech!.recipientWagonSlots!.contains(UInt8(local))
            } else {
                visible = true
            }
            result[index] = visible
            visibleUntilNextDate = visibleUntilNextDate || visible
        }
        return result
    }

    /// CODE14:164e–1890 sets the display record's TextFace byte separately from text.
    static func usesBoldFace(_ record: Record, localWagonSlot local: Int) -> Bool {
        usesBoldFace(opcode: Int(record.opcode), actorWagonSlot: record.wagonSlotBits, localWagonSlot: local)
    }

    static func usesBoldFace(opcode: Int, actorWagonSlot: Int, localWagonSlot local: Int) -> Bool {
        if actorWagonSlot == local {
            if [23,24,26,27,29,34,35,37,38,39,40,41,42,53,54,55,56,57,58,59].contains(opcode) { return true }
            if (64...66).contains(opcode) { return true }
        }
        if opcode == 71 || opcode == 88 { return true }
        return (118...119).contains(opcode) && actorWagonSlot != local
    }

    /// CODE14:09fe–0aae rebuilds a pair of indices every8 *physical* records.
    /// The optional line counter must use the original face/font/window width.
    /// Without it, visible nonempty rows make subsequent line offsets unknown;
    /// exact byte offsets, date associations and visibility remain available.
    func project(localWagonSlot local: Int,
                 strings: (Int, Int) -> String?, memberName: (Int, Int) -> String?,
                 lineCount measure: ((Record, String, Bool) -> Int?)? = nil) -> Projection {
        let visible = visibility(localWagonSlot: local)
        var rows: [ProjectedRow] = []
        var indices: [SparseIndexEntry] = []
        var date: DateMarker?
        var line: Int? = 0
        for (index, record) in records.enumerated() {
            if index.isMultiple(of: 8) {
                indices.append(.init(recordIndex: index, byteOffset: record.offset, firstLine: line))
            }
            if let marker = record.date { date = marker }
            let bold = Self.usesBoldFace(record, localWagonSlot: local)
            let text = Self.presentation(of: record, localWagonSlot: local, strings: strings, memberName: memberName)
            let count: Int?
            if !visible[index] { count = 0 }
            else if let value = text.text {
                if value.isEmpty { count = 0 }
                else if let measured = measure?(record, value, bold), (1...4).contains(measured) { count = measured }
                else { count = nil }
            } else { count = nil }
            rows.append(.init(recordIndex: index, record: record, date: date, isVisible: visible[index],
                              isBold: bold, presentation: text, firstLine: line, lineCount: count))
            if let previous = line, let count { line = previous + count } else { line = nil }
        }
        return Projection(rows: rows, sparseIndex: indices, totalLineCount: line)
    }

    enum LineCountError: Error, Equatable {
        case unsupportedPascalText
        case invalidMeasurements
        case originalWordBreakUnderflow
        case originalByteCursorWrap
    }

    /// CODE14:307e–3202 line-count component. Supply MeasureText-compatible
    /// cumulative positions: widths[0]=0; widths[i] is width of first i bytes.
    /// This preserves strict '< available' fitting, CR breaks, space backtracking,
    /// continuation indent and the four-line cap. Truncated text gets no suffix.
    static func wrappedLineCount(text: String, prefixWidths: [Int], contentWidth: Int) throws -> Int {
        guard let data = text.data(using: .macOSRoman), data.count <= 255 else { throw LineCountError.unsupportedPascalText }
        guard prefixWidths.count == data.count + 1, prefixWidths.first == 0,
              contentWidth > 21,
              zip(prefixWidths, prefixWidths.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw LineCountError.invalidMeasurements
        }
        if data.isEmpty { return 0 }
        let bytes = Array(data)
        let available = contentWidth - 6
        var threshold = available
        var cursor = 1 // Original Pascal byte index, not Swift string index.
        var rows = 0
        while cursor <= bytes.count && rows < 4 {
            let first = cursor
            while cursor <= bytes.count && prefixWidths[cursor] < threshold && bytes[cursor - 1] != 13 {
                guard cursor < 255 else { throw LineCountError.originalByteCursorWrap }
                cursor += 1
            }
            if cursor <= bytes.count {
                if bytes[cursor - 1] != 13 {
                    while cursor >= first && bytes[cursor - 1] != 32 { cursor -= 1 }
                    // The original would read before this line, possibly before
                    // the Pascal string. Reject this case instead of splitting the word.
                    guard cursor >= first else { throw LineCountError.originalWordBreakUnderflow }
                }
                guard cursor < 255 else { throw LineCountError.originalByteCursorWrap }
                cursor += 1
            }
            rows += 1
            if cursor <= bytes.count { threshold = prefixWidths[cursor] + available - 15 }
        }
        return rows
    }
}
