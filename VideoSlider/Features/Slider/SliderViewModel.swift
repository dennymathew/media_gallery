import Foundation
import Observation

@Observable
final class SliderViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var items: [SliderItem] = []
    private(set) var loadState: LoadState = .idle
    /// Bound to the pager's scroll position.
    var currentID: String?
    /// Videos start muted: muted autoplay is what iOS/WebKit and the providers allow without a tap.
    var isMuted = true

    private let repository: any SliderRepository

    init(repository: any SliderRepository) {
        self.repository = repository
    }

    var currentIndex: Int? {
        guard let currentID else { return nil }
        return items.firstIndex { $0.id == currentID }
    }

    func load() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            items = try await repository.fetchItems().filter(\.isSupported)
            currentID = items.first?.id
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func isActive(_ item: SliderItem) -> Bool {
        item.id == currentID
    }

    /// Only the current page and its neighbours keep a live player, which bounds memory and
    /// network use while still letting the next video warm up before it is swiped in.
    func isNearby(_ item: SliderItem) -> Bool {
        guard let currentIndex, let index = items.firstIndex(of: item) else { return false }
        return abs(index - currentIndex) <= 1
    }
}
