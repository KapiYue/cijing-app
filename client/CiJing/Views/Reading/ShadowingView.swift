import SwiftUI

struct ShadowingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    @StateObject private var recognizer = ShadowingRecognizer()
    let reading: ReadingSession
    @State private var index = 0
    @State private var completed: [Int: Double] = [:]

    private var sentences: [String] {
        reading.paragraphs.flatMap { paragraph in
            paragraph.english.split(whereSeparator: { ".!?".contains($0) }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) + "." }.filter { $0.count > 2 }
        }
    }
    private var current: String { sentences.indices.contains(index) ? sentences[index] : "" }
    private var accuracy: Double { recognizer.accuracy(comparedTo: current) }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 22) {
                HStack { VStack(alignment: .leading) { Text("逐句跟读").font(.system(size: 28, weight: .bold, design: .serif)); Text("先听一句，再跟着读出来").font(.caption).foregroundStyle(CiJingTheme.secondary) }; Spacer(); Text("\(min(index + 1, sentences.count))/\(sentences.count)").font(.headline) }
                ProgressView(value: Double(index), total: Double(max(1, sentences.count))).tint(CiJingTheme.green)
                Spacer()
                VStack(spacing: 20) {
                    Text(current).font(.system(size: 25, weight: .semibold, design: .serif)).lineSpacing(7).multilineTextAlignment(.center)
                    Button { speech.speak(current, slow: true) } label: { Label("播放标准美音", systemImage: "speaker.wave.2.fill") }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).cijingCard()
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("我读到的内容").font(.caption.bold()).foregroundStyle(CiJingTheme.secondary); Spacer(); if !recognizer.transcript.isEmpty { Text("匹配 \(Int(accuracy * 100))%").font(.caption.bold()).foregroundStyle(accuracy > 0.78 ? CiJingTheme.green : .orange) } }
                    Text(recognizer.transcript.isEmpty ? "点击麦克风后开始朗读…" : recognizer.transcript).foregroundStyle(recognizer.transcript.isEmpty ? CiJingTheme.secondary : CiJingTheme.ink).frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
                    if !recognizer.transcript.isEmpty { feedback }
                    if let error = recognizer.errorMessage { Text(error).font(.caption).foregroundStyle(CiJingTheme.danger) }
                }.cijingCard()
                Button { Task { if recognizer.isRecording { recognizer.stop() } else { await recognizer.start() } } } label: {
                    Image(systemName: recognizer.isRecording ? "stop.fill" : "mic.fill").font(.title).foregroundStyle(.white).frame(width: 74, height: 74).background(recognizer.isRecording ? CiJingTheme.danger : CiJingTheme.green, in: Circle()).shadow(color: CiJingTheme.green.opacity(0.25), radius: 15)
                }
                Button(index == sentences.count - 1 ? "完成跟读" : "下一句") { completed[index] = accuracy; recognizer.stop(); if index < sentences.count - 1 { index += 1; recognizer.transcript = ""; speech.speak(current, slow: true) } else { dismiss() } }.buttonStyle(PrimaryButtonStyle()).disabled(recognizer.transcript.isEmpty)
                Spacer()
            }.padding(20)
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
        .onAppear { if !current.isEmpty { speech.speak(current, slow: true) } }
        .onDisappear { speech.stop(); recognizer.stop() }
    }

    @ViewBuilder private var feedback: some View {
        if accuracy >= 0.88 { Label("很好，节奏和词序都很接近", systemImage: "checkmark.circle.fill").foregroundStyle(CiJingTheme.green) }
        else if accuracy >= 0.65 { Label("基本正确，再听一次会更自然", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange) }
        else { Label("先放慢速度，留意漏读或替换的词", systemImage: "ear").foregroundStyle(.orange) }
    }
}

