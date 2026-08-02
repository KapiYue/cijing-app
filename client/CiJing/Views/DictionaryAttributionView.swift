import SwiftUI

struct DictionaryAttributionView: View {
    let attribution: DictionaryAttribution

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let providerURL = URL(string: attribution.providerUrl) {
                    Link("由 \(attribution.provider) 提供", destination: providerURL)
                }
                ForEach(Array(attribution.sourceUrls.enumerated()), id: \.element) { index, source in
                    if let sourceURL = URL(string: source) {
                        Link(attribution.sourceUrls.count == 1 ? "查看词条来源" : "查看词条来源 \(index + 1)", destination: sourceURL)
                    }
                }
                ForEach(attribution.licenses) { license in
                    if let licenseURL = URL(string: license.url) {
                        Link("词条许可：\(license.name)", destination: licenseURL)
                    }
                }
                if let audio = attribution.audio {
                    if let sourceURL = URL(string: audio.sourceUrl) {
                        Link("查看发音来源", destination: sourceURL)
                    }
                    if let licenseURL = URL(string: audio.license.url) {
                        Link("发音许可：\(audio.license.name)", destination: licenseURL)
                    }
                }
                Text("英文词条及其改编内容按上述许可提供；发音素材可能采用独立许可。")
                    .foregroundStyle(CiJingTheme.secondary)
            }
            .font(.caption)
            .padding(.top, 8)
        } label: {
            Label("词典来源与许可", systemImage: "doc.text.magnifyingglass")
                .font(.caption.bold())
                .foregroundStyle(CiJingTheme.purple)
        }
    }
}

struct ThirdPartyCreditsView: View {
    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    creditCard(
                        title: "Free Dictionary API 与 Wiktionary",
                        copy: "英文释义、音标及部分发音由 Free Dictionary API 提供。词条通常源自 Wiktionary，并按 CC BY-SA 3.0 提供；发音素材的作者、来源与许可会随具体条目显示。",
                        links: [
                            ("Free Dictionary API", "https://dictionaryapi.dev/"),
                            ("CC BY-SA 3.0", "https://creativecommons.org/licenses/by-sa/3.0/"),
                        ]
                    )
                    creditCard(
                        title: "OpenRouter 与 Qwen",
                        copy: "中文语境解释、例句和个性化短文由所配置的 Qwen 模型经 OpenRouter 生成。AI 内容可能不准确，使用前请结合原文核对。",
                        links: [
                            ("OpenRouter", "https://openrouter.ai/"),
                            ("Qwen3.6 Flash", "https://openrouter.ai/qwen/qwen3.6-flash"),
                        ]
                    )
                    Text("具体词条和发音的来源链接以查词结果及已收藏词条中保存的许可信息为准。")
                        .font(.caption)
                        .foregroundStyle(CiJingTheme.secondary)
                        .lineSpacing(4)
                }
                .padding(18)
            }
        }
        .navigationTitle("第三方内容与许可")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditCard(title: String, copy: String, links: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(copy).font(.subheadline).foregroundStyle(CiJingTheme.secondary).lineSpacing(5)
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                let (label, url) = link
                if let destination = URL(string: url) {
                    Link(label, destination: destination)
                        .font(.subheadline.bold())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cijingCard(padding: 20)
    }
}
