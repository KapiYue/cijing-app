import SwiftUI

struct ShadowingView: View {
    @EnvironmentObject private var store: AppStore
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
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("逐句跟读").font(.system(size: 28, weight: .bold, design: .serif))
                            Text("先听一句，再跟着读出来").font(.caption).foregroundStyle(CiJingTheme.secondary)
                        }
                        Spacer()
                        Text("\(min(index + 1, sentences.count))/\(sentences.count)").font(.headline)
                    }
                    ProgressView(value: Double(index), total: Double(max(1, sentences.count))).tint(CiJingTheme.green)

                    VStack(spacing: 18) {
                        Text(current)
                            .font(.system(size: 25, weight: .semibold, design: .serif))
                            .lineSpacing(7)
                            .lineLimit(nil)
                            .minimumScaleFactor(0.82)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Button { speech.speak(current, slow: true) } label: {
                            Label(speech.isSpeaking ? "正在播放示范发音" : "播放示范发音", systemImage: speech.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                        }.buttonStyle(.borderedProminent)
                        if let error = speech.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(CiJingTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .cijingCard()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("我读到的内容").font(.caption.bold()).foregroundStyle(CiJingTheme.secondary)
                            Spacer()
                            if recognizer.isTranscribing {
                                ProgressView().controlSize(.small)
                                Text("正在识别").font(.caption.bold()).foregroundStyle(CiJingTheme.purple)
                            } else if !recognizer.transcript.isEmpty {
                                Text("匹配 \(Int(accuracy * 100))%")
                                    .font(.caption.bold()).foregroundStyle(accuracy > 0.78 ? CiJingTheme.green : .orange)
                            }
                        }
                        Text(transcriptPlaceholder)
                            .foregroundStyle(recognizer.transcript.isEmpty ? CiJingTheme.secondary : CiJingTheme.ink)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
                        if !recognizer.transcript.isEmpty { feedback }
                        if let error = recognizer.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(CiJingTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.cijingCard()

                    Button {
                        Task {
                            if recognizer.isRecording {
                                recognizer.stop()
                            } else {
                                speech.stop()
                                await recognizer.start()
                            }
                        }
                    } label: {
                        Image(systemName: recognizer.isRecording ? "stop.fill" : "mic.fill")
                            .font(.title).foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(recognizer.isRecording ? CiJingTheme.danger : CiJingTheme.green, in: Circle())
                            .shadow(color: CiJingTheme.green.opacity(0.25), radius: 15)
                    }
                    .disabled(recognizer.isTranscribing)
                    .accessibilityLabel(recognizer.isRecording ? "停止录音" : "开始录音")

                    Text(recordingStatus)
                        .font(.caption.bold())
                        .foregroundStyle(recognizer.isRecording ? CiJingTheme.danger : CiJingTheme.secondary)

                    Button(index == sentences.count - 1 ? "完成跟读" : "下一句") {
                        completed[index] = accuracy
                        if index < sentences.count - 1 {
                            store.playHaptic(.step)
                            index += 1
                            recognizer.transcript = ""
                            recognizer.errorMessage = nil
                            speech.speak(current, slow: true)
                        } else {
                            store.playHaptic(.completion)
                            dismiss()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(recognizer.transcript.isEmpty || recognizer.isRecording || recognizer.isTranscribing)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } } }
        .onAppear { if !current.isEmpty { speech.speak(current, slow: true) } }
        .onDisappear { speech.stop(); recognizer.cancel() }
    }

    private var transcriptPlaceholder: String {
        if !recognizer.transcript.isEmpty { return recognizer.transcript }
        if recognizer.isTranscribing { return "录音已结束，正在整理你读到的内容…" }
        return recognizer.isRecording ? "正在听，请读完整句后点击红色停止按钮…" : "点击麦克风后开始朗读…"
    }

    private var recordingStatus: String {
        if recognizer.isTranscribing { return "正在识别录音，请稍候…" }
        return recognizer.isRecording ? "正在录音 · 点击红色按钮结束" : "点击麦克风开始录音"
    }

    @ViewBuilder private var feedback: some View {
        if accuracy >= 0.88 { Label("很好，节奏和词序都很接近", systemImage: "checkmark.circle.fill").foregroundStyle(CiJingTheme.green) }
        else if accuracy >= 0.65 { Label("基本正确，再听一次会更自然", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange) }
        else { Label("先放慢速度，留意漏读或替换的词", systemImage: "ear").foregroundStyle(.orange) }
    }
}
