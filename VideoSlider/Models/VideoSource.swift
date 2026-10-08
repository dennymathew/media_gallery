import Foundation

/// Where a video link points to, which decides how it can be played.
enum VideoSource: Hashable, Sendable {
    /// YouTube video id. Played through the official IFrame Player API.
    case youtube(id: String)
    /// Vimeo video id, plus the privacy hash for unlisted videos. Played through Vimeo Player.js.
    case vimeo(id: String, hash: String?)
    /// A direct media URL (HLS `.m3u8`, `.mp4`, …) that AVPlayer can play natively.
    case direct(URL)
    /// A page on any other platform. Resolved to an embeddable player via oEmbed and controlled
    /// through the generic HTML5 `<video>` bridge.
    case embed(URL)
    /// Anything we can't play in-app (non-web links).
    case unsupported(URL)

    var thumbnailURL: URL? {
        switch self {
        case .youtube(let id):
            URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
        case .vimeo(let id, _):
            // Unofficial but stable thumbnail redirect; the oEmbed API is the official alternative.
            URL(string: "https://vumbnail.com/\(id).jpg")
        case .direct, .embed, .unsupported:
            nil
        }
    }
}
