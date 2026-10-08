import Foundation

/// A single page in the slider, as delivered by the backend.
/// Decoding is driven by the `type` discriminator; unknown types are kept as
/// `.unknown` so new backend item types don't break older app versions.
enum SliderItem: Identifiable, Decodable, Hashable {
    case image(ImageItem)
    case video(VideoItem)
    case virtualTour(TourItem)
    case unknown(id: String, type: String)

    struct ImageItem: Hashable, Sendable {
        let id: String
        let url: URL
    }

    struct VideoItem: Hashable, Sendable {
        let id: String
        let url: URL
        let source: VideoSource
        /// Optional, backend-resolved player URL (e.g. from oEmbed). Skips client-side resolution.
        var embedURL: URL?
        var thumbnailURL: URL?
    }

    /// An interactive 360° tour hosted by a provider such as Ogulo, shown in a web view.
    struct TourItem: Hashable, Sendable {
        let id: String
        let url: URL
        var thumbnailURL: URL?
    }

    var id: String {
        switch self {
        case .image(let item): item.id
        case .video(let item): item.id
        case .virtualTour(let item): item.id
        case .unknown(let id, _): id
        }
    }

    var isSupported: Bool {
        if case .unknown = self { return false }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, url
        case embedURL = "embedUrl"
        case thumbnailURL = "thumbnailUrl"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "image":
            self = .image(ImageItem(id: id, url: try container.decode(URL.self, forKey: .url)))
        case "video":
            let url = try container.decode(URL.self, forKey: .url)
            self = .video(VideoItem(
                id: id,
                url: url,
                source: VideoURLParser.parse(url),
                embedURL: try container.decodeIfPresent(URL.self, forKey: .embedURL),
                thumbnailURL: try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
            ))
        case "virtualTour":
            self = .virtualTour(TourItem(
                id: id,
                url: try container.decode(URL.self, forKey: .url),
                thumbnailURL: try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
            ))
        default:
            self = .unknown(id: id, type: type)
        }
    }
}
