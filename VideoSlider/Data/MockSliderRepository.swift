import Foundation

/// Loads slider items from the bundled `mock_slider.json`, simulating a network call.
struct MockSliderRepository: SliderRepository {
    var fileName = "mock_slider"
    var simulatedDelay: Duration = .milliseconds(400)

    func fetchItems() async throws -> [SliderItem] {
        try await Task.sleep(for: simulatedDelay)
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([SliderItem].self, from: data)
    }
}
