import SwiftUI

struct SliderView: View {
    @Bindable var viewModel: SliderViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.loadState {
            case .idle, .loading:
                ProgressView().tint(.white)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load slides", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await viewModel.load() } }
                }
                .foregroundStyle(.white)
            case .loaded:
                pager
                    .ignoresSafeArea()
                controls
            }
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.load() }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    SlideView(
                        item: item,
                        isActive: viewModel.isActive(item) && scenePhase == .active,
                        isNearby: viewModel.isNearby(item),
                        isMuted: viewModel.isMuted
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .clipped()
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $viewModel.currentID)
        .scrollIndicators(.hidden)
    }

    private var controls: some View {
        VStack {
            HStack {
                Spacer()
                if currentItemIsVideo {
                    Button {
                        viewModel.isMuted.toggle()
                    } label: {
                        Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(viewModel.isMuted ? "Unmute" : "Mute")
                }
            }
            Spacer()
            PageIndicator(count: viewModel.items.count, currentIndex: viewModel.currentIndex ?? 0)
        }
        .padding()
    }

    private var currentItemIsVideo: Bool {
        guard let index = viewModel.currentIndex, case .video = viewModel.items[index] else { return false }
        return true
    }
}

private struct SlideView: View {
    let item: SliderItem
    let isActive: Bool
    let isNearby: Bool
    let isMuted: Bool

    var body: some View {
        switch item {
        case .image(let image):
            ImageSlideView(url: image.url)
        case .video(let video):
            VideoSlideView(item: video, isActive: isActive, isNearby: isNearby, isMuted: isMuted)
        case .virtualTour(let tour):
            TourSlideView(item: tour, isActive: isActive)
        case .unknown:
            EmptyView()
        }
    }
}

private struct PageIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? .white : .white.opacity(0.4))
                    .frame(width: index == currentIndex ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: currentIndex)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect()
        .accessibilityElement()
        .accessibilityLabel("Page \(currentIndex + 1) of \(count)")
    }
}

#Preview {
    SliderView(viewModel: SliderViewModel(repository: MockSliderRepository()))
}
