import Foundation

/// Source of slider items. Swap `MockSliderRepository` for a real API client later.
protocol SliderRepository: Sendable {
    func fetchItems() async throws -> [SliderItem]
}
