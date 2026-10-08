import Foundation

/// Turns a backend-provided video link into a `VideoSource`.
enum VideoURLParser {
    private static let directExtensions: Set<String> = ["m3u8", "mp4", "mov", "m4v"]

    static func parse(_ url: URL) -> VideoSource {
        let host = (url.host() ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        let components = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be", let id = components.first {
            return .youtube(id: id)
        }

        if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let id = queryValue("v", in: url) {
                return .youtube(id: id)
            }
            if components.count >= 2, ["embed", "shorts", "live", "v"].contains(components[0]) {
                return .youtube(id: components[1])
            }
        }

        if host == "player.vimeo.com", components.count >= 2, components[0] == "video" {
            return .vimeo(id: components[1], hash: queryValue("h", in: url))
        }

        if host == "vimeo.com" {
            // vimeo.com/{id}, vimeo.com/{id}/{hash}, vimeo.com/channels/x/{id}, ...
            if let index = components.firstIndex(where: { Int($0) != nil }) {
                let next = components.index(after: index)
                let hash = next < components.endIndex ? components[next] : nil
                return .vimeo(id: components[index], hash: hash)
            }
        }

        if directExtensions.contains(url.pathExtension.lowercased()) {
            return .direct(url)
        }

        if let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            return .embed(url)
        }

        return .unsupported(url)
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
