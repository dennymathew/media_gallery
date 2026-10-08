import Foundation

/// The embeddable player for a video page.
nonisolated struct ResolvedEmbed: Sendable {
    let playerURL: URL
    let thumbnailURL: URL?
    /// False when no player could be found and the page itself is loaded instead.
    let isPlayer: Bool
}

/// Turns a link to a video page on any platform into an embeddable player URL using oEmbed
/// (https://oembed.com). Ideally the backend does this once and sends `embedUrl`/`thumbnailUrl`;
/// this client-side resolver is the fallback.
actor EmbedResolver {
    static let shared = EmbedResolver()

    /// Providers whose oEmbed endpoint is known, so their (heavy) pages don't need fetching.
    /// Any other site is handled by oEmbed discovery on the page itself.
    private static let knownEndpoints: [(hostSuffix: String, endpoint: String)] = [
        ("dailymotion.com", "https://www.dailymotion.com/services/oembed"),
        ("dai.ly", "https://www.dailymotion.com/services/oembed"),
        ("wistia.com", "https://fast.wistia.com/oembed.json"),
        ("wistia.net", "https://fast.wistia.com/oembed.json"),
        ("streamable.com", "https://api.streamable.com/oembed.json"),
        ("loom.com", "https://www.loom.com/v1/oembed"),
    ]

    private static let pageUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private var cache: [URL: ResolvedEmbed] = [:]

    func resolve(pageURL: URL, embedURL: URL?, thumbnailURL: URL?) async -> ResolvedEmbed {
        if let embedURL {
            return ResolvedEmbed(playerURL: embedURL, thumbnailURL: thumbnailURL, isPlayer: true)
        }
        if let cached = cache[pageURL] {
            return cached
        }
        let resolved = (try? await resolveViaOEmbed(pageURL))
            ?? ResolvedEmbed(playerURL: pageURL, thumbnailURL: thumbnailURL, isPlayer: false)
        cache[pageURL] = resolved
        return resolved
    }

    private func resolveViaOEmbed(_ pageURL: URL) async throws -> ResolvedEmbed? {
        guard let endpoint = try await oEmbedEndpoint(for: pageURL) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(OEmbedResponse.self, from: data)

        guard
            let html = response.html,
            let src = Self.firstMatch(of: /<iframe\b[^>]*\bsrc\s*=\s*["']([^"']+)["']/, in: html),
            let playerURL = URL(string: Self.decodeEntities(src), relativeTo: endpoint)?.absoluteURL,
            playerURL.scheme == "https"
        else { return nil }

        let thumbnailURL = response.thumbnailURL.flatMap { URL(string: $0, relativeTo: endpoint)?.absoluteURL }
        return ResolvedEmbed(playerURL: playerURL, thumbnailURL: thumbnailURL, isPlayer: true)
    }

    private func oEmbedEndpoint(for pageURL: URL) async throws -> URL? {
        let host = pageURL.host()?.lowercased() ?? ""
        if let known = Self.knownEndpoints.first(where: { host == $0.hostSuffix || host.hasSuffix("." + $0.hostSuffix) }) {
            var components = URLComponents(string: known.endpoint)
            components?.queryItems = [
                URLQueryItem(name: "url", value: pageURL.absoluteString),
                URLQueryItem(name: "format", value: "json"),
            ]
            return components?.url
        }
        return try await discoverEndpoint(on: pageURL)
    }

    /// oEmbed discovery: `<link rel="alternate" type="application/json+oembed" href="…">` in the page.
    private func discoverEndpoint(on pageURL: URL) async throws -> URL? {
        var request = URLRequest(url: pageURL)
        request.setValue(Self.pageUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(decoding: data.prefix(1_000_000), as: UTF8.self)

        for match in html.matches(of: /<link\b[^>]*>/) {
            let tag = String(match.output)
            guard tag.localizedCaseInsensitiveContains("json+oembed"),
                  let href = Self.firstMatch(of: /\bhref\s*=\s*["']([^"']+)["']/, in: tag)
            else { continue }
            return URL(string: Self.decodeEntities(href), relativeTo: pageURL)?.absoluteURL
        }
        return nil
    }

    private static func firstMatch(of regex: Regex<(Substring, Substring)>, in text: String) -> String? {
        text.firstMatch(of: regex.ignoresCase()).map { String($0.output.1) }
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

private nonisolated struct OEmbedResponse: Decodable, Sendable {
    let html: String?
    let thumbnailURL: String?

    private enum CodingKeys: String, CodingKey {
        case html
        case thumbnailURL = "thumbnail_url"
    }
}
