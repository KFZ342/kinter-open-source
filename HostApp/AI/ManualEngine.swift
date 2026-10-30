import Foundation

/// 本地程序手册引擎。
/// 数据通过 xcodegen 打包进 Bundle。自动兼容目录结构或扁平化拷贝。
final class ManualEngine {
    static let shared = ManualEngine()
    private init() {}

    struct Chapter {
        let id: String
        let title: String
        let summary: String
        let keywords: [String]
        let file: String
        var content: String = ""
    }

    private var chapters: [Chapter] = []
    private var loaded = false

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        let bundle = Bundle.main.resourceURL!
        // 尝试两种路径：带 Manual 目录，或拍平在根目录
        var base: URL? = bundle.appendingPathComponent("Manual")
        if !FileManager.default.fileExists(atPath: base!.appendingPathComponent("index.json").path) {
            base = bundle
        }

        guard let finalBase = base,
              let data = try? Data(contentsOf: finalBase.appendingPathComponent("index.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["chapters"] as? [[String: Any]] else {
            return
        }

        chapters = list.compactMap { item -> Chapter? in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  let file = item["file"] as? String else { return nil }
            let summary = item["summary"] as? String ?? ""
            let keywords = item["keywords"] as? [String] ?? []

            // 尝试寻找正文文件
            var content = ""
            let paths = [
                finalBase.appendingPathComponent(file),
                finalBase.appendingPathComponent((file as NSString).lastPathComponent)
            ]
            for p in paths {
                if let s = try? String(contentsOf: p, encoding: .utf8) {
                    content = s
                    break
                }
            }

            return Chapter(id: id, title: title, summary: summary,
                           keywords: keywords, file: file, content: content)
        }
    }

    var chapterCount: Int { loadIfNeeded(); return chapters.count }

    func listChapters() -> [[String: Any]] {
        loadIfNeeded()
        return chapters.map { [
            "id": $0.id, "title": $0.title, "summary": $0.summary,
            "keywords": $0.keywords, "size": $0.content.count
        ] }
    }

    func readChapter(id: String) -> [String: Any]? {
        loadIfNeeded()
        guard let ch = chapters.first(where: { $0.id == id }) else { return nil }
        return ["id": ch.id, "title": ch.title, "content": ch.content]
    }

    func search(query: String, limit: Int = 5) -> [[String: Any]] {
        loadIfNeeded()
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        struct Hit { let ch: Chapter; let score: Int; let snippets: [String] }
        var hits: [Hit] = []

        for ch in chapters {
            var score = 0
            let titleLower = ch.title.lowercased()
            let kwLower = ch.keywords.joined(separator: " ").lowercased()
            let bodyLower = ch.content.lowercased()

            for t in terms {
                if titleLower.contains(t) { score += 10 }
                if kwLower.contains(t)    { score += 6 }
                if bodyLower.contains(t)  { score += 2 }
            }
            guard score > 0 else { continue }

            var snippets: [String] = []
            let paragraphs = ch.content.components(separatedBy: "\n\n")
            for p in paragraphs where snippets.count < 3 {
                let pl = p.lowercased()
                if terms.contains(where: { pl.contains($0) }) {
                    let trimmed = p.count > 300 ? String(p.prefix(300)) + "…" : p
                    snippets.append(trimmed)
                }
            }
            hits.append(Hit(ch: ch, score: score, snippets: snippets))
        }

        hits.sort { $0.score > $1.score }
        return hits.prefix(limit).map { h in
            ["id": h.ch.id, "title": h.ch.title, "summary": h.ch.summary, "score": h.score, "snippets": h.snippets]
        }
    }
}
