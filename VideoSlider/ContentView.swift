import SwiftUI

struct ContentView: View {
    @State private var viewModel = SliderViewModel(repository: MockSliderRepository())

    var body: some View {
        SliderView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
