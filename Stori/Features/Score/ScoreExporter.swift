//
//  ScoreExporter.swift
//  Stori
//
//  Export score to PDF and MusicXML formats
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Page Size

enum ScorePageSize: String, CaseIterable {
    case letter = "Letter"
    case a4 = "A4"
    case legal = "Legal"
    case tabloid = "Tabloid"
    
    var size: CGSize {
        switch self {
        case .letter: return CGSize(width: 612, height: 792)   // 8.5 x 11"
        case .a4: return CGSize(width: 595, height: 842)       // 210 x 297mm
        case .legal: return CGSize(width: 612, height: 1008)   // 8.5 x 14"
        case .tabloid: return CGSize(width: 792, height: 1224) // 11 x 17"
        }
    }
}

// MARK: - Score PDF Exporter

class ScorePDFExporter {
    
    // MARK: - Configuration
    
    struct ExportConfiguration {
        var pageSize: ScorePageSize = .letter
        var margins: EdgeInsets = EdgeInsets(top: 72, leading: 72, bottom: 72, trailing: 72)
        var title: String = ""
        var composer: String = ""
        var showPageNumbers: Bool = true
        var staffSpacing: CGFloat = 80
        var measuresPerLine: Int = 4
    }
    
    private let renderer = StaffRenderer()
    private let quantizer = NotationQuantizer()
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    // MARK: - Export to PDF
    
    /// Export a MIDI region to PDF
    func exportToPDF(
        region: MIDIRegion,
        configuration: ScoreConfiguration,
        exportConfig: ExportConfiguration = ExportConfiguration()
    ) -> Data? {
        // Quantize MIDI to notation
        let measures = quantizer.quantize(
            notes: region.notes,
            timeSignature: configuration.timeSignature,
            tempo: configuration.tempo
        )
        
        guard !measures.isEmpty else { return nil }
        
        let pageSize = exportConfig.pageSize.size
        let contentWidth = pageSize.width - exportConfig.margins.leading - exportConfig.margins.trailing
        let contentHeight = pageSize.height - exportConfig.margins.top - exportConfig.margins.bottom
        
        // Calculate pages
        let measuresPerLine = exportConfig.measuresPerLine
        let linesPerPage = Int(contentHeight / exportConfig.staffSpacing)
        let measuresPerPage = measuresPerLine * linesPerPage
        let pageCount = max(1, (measures.count + measuresPerPage - 1) / measuresPerPage)
        
        // Create PDF data
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }
        
        for pageIndex in 0..<pageCount {
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            pdfContext.beginPage(mediaBox: &mediaBox)
            
            // Flip coordinate system for proper text rendering
            pdfContext.translateBy(x: 0, y: pageSize.height)
            pdfContext.scaleBy(x: 1, y: -1)
            
            // Draw page content
            drawPage(
                context: pdfContext,
                pageIndex: pageIndex,
                measures: measures,
                configuration: configuration,
                exportConfig: exportConfig,
                pageSize: pageSize,
                contentWidth: contentWidth
            )
            
            // Draw page number
            if exportConfig.showPageNumbers {
                drawPageNumber(
                    context: pdfContext,
                    pageIndex: pageIndex,
                    totalPages: pageCount,
                    pageSize: pageSize,
                    margins: exportConfig.margins
                )
            }
            
            pdfContext.endPage()
        }
        
        pdfContext.closePDF()
        
        return pdfData as Data
    }
    
    private func drawPage(
        context: CGContext,
        pageIndex: Int,
        measures: [ScoreMeasure],
        configuration: ScoreConfiguration,
        exportConfig: ExportConfiguration,
        pageSize: CGSize,
        contentWidth: CGFloat
    ) {
        let margins = exportConfig.margins
        var currentY = margins.top
        
        // Draw title on first page
        if pageIndex == 0 && !exportConfig.title.isEmpty {
            drawTitle(context: context, title: exportConfig.title, pageSize: pageSize, y: &currentY)
            
            if !exportConfig.composer.isEmpty {
                drawComposer(context: context, composer: exportConfig.composer, pageSize: pageSize, y: &currentY)
            }
            
            currentY += 20 // Extra spacing after header
        }
        
        // Calculate which measures to draw on this page
        let measuresPerLine = exportConfig.measuresPerLine
        let linesPerPage = Int((pageSize.height - currentY - margins.bottom) / exportConfig.staffSpacing)
        let measuresPerPage = measuresPerLine * linesPerPage
        let startMeasure = pageIndex * measuresPerPage
        let endMeasure = min(startMeasure + measuresPerPage, measures.count)
        
        // Draw staves
        var measureIndex = startMeasure
        let measureWidth = contentWidth / CGFloat(measuresPerLine)
        
        while measureIndex < endMeasure && currentY + exportConfig.staffSpacing < pageSize.height - margins.bottom {
            let lineStartX = margins.leading
            
            // Draw one line of staves
            for linePosition in 0..<measuresPerLine {
                if measureIndex >= measures.count { break }
                
                let x = lineStartX + CGFloat(linePosition) * measureWidth
                
                // Draw staff lines
                drawStaffLines(
                    context: context,
                    x: x,
                    y: currentY,
                    width: measureWidth,
                    spacing: renderer.staffLineSpacing
                )
                
                // Draw clef on first measure of line
                if linePosition == 0 {
                    drawClefText(
                        context: context,
                        clef: configuration.clef,
                        x: x + 5,
                        y: currentY + renderer.staffHeight / 2
                    )
                }
                
                // Draw bar line at end
                drawBarLine(
                    context: context,
                    x: x + measureWidth,
                    y: currentY,
                    height: renderer.staffHeight
                )
                
                measureIndex += 1
            }
            
            currentY += exportConfig.staffSpacing
        }
    }
    
    private func drawTitle(context: CGContext, title: String, pageSize: CGSize, y: inout CGFloat) {
        let font = NSFont.boldSystemFont(ofSize: 24)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let attributedString = NSAttributedString(string: title, attributes: attributes)
        let size = attributedString.size()
        
        let x = (pageSize.width - size.width) / 2
        attributedString.draw(at: CGPoint(x: x, y: y))
        
        y += size.height + 8
    }
    
    private func drawComposer(context: CGContext, composer: String, pageSize: CGSize, y: inout CGFloat) {
        let font = NSFont.systemFont(ofSize: 14)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.darkGray
        ]
        
        let attributedString = NSAttributedString(string: composer, attributes: attributes)
        let size = attributedString.size()
        
        let x = pageSize.width - 72 - size.width // Right-aligned with margin
        attributedString.draw(at: CGPoint(x: x, y: y))
        
        y += size.height + 4
    }
    
    private func drawPageNumber(
        context: CGContext,
        pageIndex: Int,
        totalPages: Int,
        pageSize: CGSize,
        margins: EdgeInsets
    ) {
        let text = "Page \(pageIndex + 1) of \(totalPages)"
        let font = NSFont.systemFont(ofSize: 10)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.gray
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let size = attributedString.size()
        
        let x = (pageSize.width - size.width) / 2
        let y = pageSize.height - margins.bottom + 20
        
        attributedString.draw(at: CGPoint(x: x, y: y))
    }
    
    private func drawStaffLines(context: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, spacing: CGFloat) {
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(0.5)
        
        for i in 0..<5 {
            let lineY = y + CGFloat(i) * spacing
            context.move(to: CGPoint(x: x, y: lineY))
            context.addLine(to: CGPoint(x: x + width, y: lineY))
        }
        
        context.strokePath()
    }
    
    private func drawBarLine(context: CGContext, x: CGFloat, y: CGFloat, height: CGFloat) {
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x, y: y + height))
        context.strokePath()
    }
    
    private func drawClefText(context: CGContext, clef: Clef, x: CGFloat, y: CGFloat) {
        let symbol = clef.glyph
        let font = NSFont.systemFont(ofSize: 32)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let attributedString = NSAttributedString(string: symbol, attributes: attributes)
        attributedString.draw(at: CGPoint(x: x, y: y - 16))
    }
    
    // MARK: - Save Dialog
    
    /// Show save dialog and export PDF
    func exportWithDialog(
        region: MIDIRegion,
        configuration: ScoreConfiguration,
        exportConfig: ExportConfiguration = ExportConfiguration()
    ) {
        guard let pdfData = exportToPDF(region: region, configuration: configuration, exportConfig: exportConfig) else {
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(region.name).pdf"
        savePanel.title = "Export Score as PDF"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try pdfData.write(to: url)
                    
                    // Open in Preview
                    NSWorkspace.shared.open(url)
                } catch {
                }
            }
        }
    }
}

// MARK: - MusicXML Exporter

class MusicXMLExporter {
    
    private let quantizer = NotationQuantizer()
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    /// Export a MIDI region to MusicXML format
    func exportToMusicXML(
        region: MIDIRegion,
        configuration: ScoreConfiguration
    ) -> String {
        let measures = quantizer.quantize(
            notes: region.notes,
            timeSignature: configuration.timeSignature,
            tempo: configuration.tempo
        )
        
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <work>
            <work-title>\(escapeXML(region.name))</work-title>
          </work>
          <identification>
            <creator type="composer">Stori</creator>
            <encoding>
              <software>Stori</software>
              <encoding-date>\(dateString())</encoding-date>
            </encoding>
          </identification>
          <part-list>
            <score-part id="P1">
              <part-name>\(escapeXML(region.name))</part-name>
            </score-part>
          </part-list>
          <part id="P1">
        
        """
        
        // Export each measure
        for (index, measure) in measures.enumerated() {
            xml += exportMeasure(measure, index: index + 1, configuration: configuration, isFirst: index == 0)
        }
        
        xml += """
          </part>
        </score-partwise>
        """
        
        return xml
    }
    
    private func exportMeasure(
        _ measure: ScoreMeasure,
        index: Int,
        configuration: ScoreConfiguration,
        isFirst: Bool
    ) -> String {
        var xml = "    <measure number=\"\(index)\">\n"
        
        // Add attributes on first measure
        if isFirst {
            xml += """
                  <attributes>
                    <divisions>4</divisions>
                    <key>
                      <fifths>\(configuration.keySignature.sharps)</fifths>
                    </key>
                    <time>
                      <beats>\(configuration.timeSignature.beats)</beats>
                      <beat-type>\(configuration.timeSignature.beatValue)</beat-type>
                    </time>
                    <clef>
                      <sign>\(clefSign(configuration.clef))</sign>
                      <line>\(clefLine(configuration.clef))</line>
                    </clef>
                  </attributes>
            
            """
        }
        
        // Export notes
        for note in measure.notes {
            xml += exportNote(note, configuration: configuration)
        }
        
        // Export rests
        for rest in measure.rests {
            xml += exportRest(rest)
        }
        
        xml += "    </measure>\n"
        return xml
    }
    
    private func exportNote(_ note: ScoreNote, configuration: ScoreConfiguration) -> String {
        let (step, alter, octave) = pitchComponents(note.pitch)
        let duration = Int(note.displayDuration.rawValue * 4) // divisions = 4
        
        var xml = """
              <note>
                <pitch>
                  <step>\(step)</step>
        
        """
        
        if alter != 0 {
            xml += "          <alter>\(alter)</alter>\n"
        }
        
        xml += """
                  <octave>\(octave)</octave>
                </pitch>
                <duration>\(duration)</duration>
                <type>\(noteType(note.displayDuration))</type>
        
        """
        
        // Add dots
        for _ in 0..<note.dotCount {
            xml += "        <dot/>\n"
        }
        
        // Add tie
        if note.tieFromPrevious {
            xml += "        <tie type=\"stop\"/>\n"
        }
        if note.tieToNext {
            xml += "        <tie type=\"start\"/>\n"
        }
        
        xml += "      </note>\n"
        return xml
    }
    
    private func exportRest(_ rest: ScoreRest) -> String {
        let duration = Int(rest.duration.rawValue * 4)
        
        return """
              <note>
                <rest/>
                <duration>\(duration)</duration>
                <type>\(noteType(rest.duration))</type>
              </note>
        
        """
    }
    
    private func pitchComponents(_ pitch: UInt8) -> (step: String, alter: Int, octave: Int) {
        let noteNames = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
        let alterations = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
        
        let pitchClass = Int(pitch) % 12
        let octave = Int(pitch) / 12 - 1
        
        return (noteNames[pitchClass], alterations[pitchClass], octave)
    }
    
    private func noteType(_ duration: NoteDuration) -> String {
        switch duration {
        case .whole: return "whole"
        case .half: return "half"
        case .quarter: return "quarter"
        case .eighth: return "eighth"
        case .sixteenth: return "16th"
        case .thirtySecond: return "32nd"
        case .sixtyFourth: return "64th"
        }
    }
    
    private func clefSign(_ clef: Clef) -> String {
        switch clef {
        case .treble: return "G"
        case .bass: return "F"
        case .alto, .tenor: return "C"
        case .percussion: return "percussion"
        }
    }
    
    private func clefLine(_ clef: Clef) -> Int {
        switch clef {
        case .treble: return 2
        case .bass: return 4
        case .alto: return 3
        case .tenor: return 4
        case .percussion: return 3
        }
    }
    
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    // MARK: - Save Dialog
    
    /// Show save dialog and export MusicXML
    func exportWithDialog(
        region: MIDIRegion,
        configuration: ScoreConfiguration
    ) {
        let xmlString = exportToMusicXML(region: region, configuration: configuration)
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "musicxml") ?? .xml]
        savePanel.nameFieldStringValue = "\(region.name).musicxml"
        savePanel.title = "Export Score as MusicXML"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try xmlString.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                }
            }
        }
    }
}

// MARK: - Score Print Controller

class ScorePrintController {
    
    private let renderer = StaffRenderer()
    private let quantizer = NotationQuantizer()
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    /// Print the score
    func printScore(
        region: MIDIRegion,
        configuration: ScoreConfiguration
    ) {
        // Create a print view
        let printView = ScorePrintView(
            region: region,
            configuration: configuration,
            renderer: renderer,
            quantizer: quantizer
        )
        
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        
        let hostingView = NSHostingView(rootView: printView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 612, height: 792)
        
        let printOperation = NSPrintOperation(view: hostingView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.run()
    }
}

// MARK: - Score Print View

struct ScorePrintView: View {
    let region: MIDIRegion
    let configuration: ScoreConfiguration
    let renderer: StaffRenderer
    let quantizer: NotationQuantizer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(region.name)
                .font(.title)
                .fontWeight(.bold)
            
            // Score content
            Canvas { context, size in
                let measures = quantizer.quantize(
                    notes: region.notes,
                    timeSignature: configuration.timeSignature,
                    tempo: configuration.tempo
                )
                
                var yOffset: CGFloat = 40
                let measureWidth: CGFloat = (size.width - 40) / 4
                
                for (index, measure) in measures.enumerated() {
                    let lineIndex = index / 4
                    let measureIndex = index % 4
                    
                    let x: CGFloat = 20 + CGFloat(measureIndex) * measureWidth
                    let y = yOffset + CGFloat(lineIndex) * 80
                    
                    // Draw staff lines
                    renderer.drawStaffLines(
                        context: context,
                        width: measureWidth,
                        yOffset: y
                    )
                    
                    // Draw notes
                    for note in measure.notes {
                        renderer.drawNote(
                            context: context,
                            note: note,
                            x: x + 20 + CGFloat(note.startBeat / configuration.timeSignature.measureDuration) * (measureWidth - 40),
                            clef: configuration.clef,
                            yOffset: y,
                            isSelected: false
                        )
                    }
                }
            }
            .frame(minHeight: 600)
        }
        .padding()
    }
}

