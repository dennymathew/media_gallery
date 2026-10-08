import SwiftUI

/// A virtual tour page (e.g. Ogulo). The tour loads automatically as a live preview that takes no
/// touches, so horizontal swipes keep paging the slider (a 360° tour pans on drag too). "Explore tour"
/// opens it full screen and interactive.
struct TourSlideView: View {
    let item: SliderItem.TourItem
    let isActive: Bool

    @State private var isLoaded = false
    @State private var failure: String?
    @State private var isExploring = false

    var body: some View {
        ZStack {
            Color.black

            // Only the visible tour is kept alive: 360° tours are heavy WebGL pages. It is also
            // unloaded while the explorer shows its own interactive copy.
            if isActive && !isExploring {
                TourWebView(
                    url: item.url,
                    isInteractive: false,
                    onLoaded: { isLoaded = true },
                    onFailed: { failure = $0 }
                )
                .padding(Self.previewInsets)
            }

            if !isLoaded || !isActive || isExploring {
                poster
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if let failure {
                ContentUnavailableView("Tour unavailable", systemImage: "view.3d", description: Text(failure))
                    .foregroundStyle(.white)
                    .background(.black)
            } else {
                VStack {
                    Spacer()
                    Button {
                        isExploring = true
                    } label: {
                        Label("Explore tour", systemImage: "view.3d")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    // Clear of the slider's page indicator and the home indicator.
                    .padding(.bottom, 110)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: isLoaded)
        .onChange(of: isActive) {
            // The preview web view is torn down when swiped away; show the poster until it reloads.
            if !isActive { isLoaded = false }
        }
        .fullScreenCover(isPresented: $isExploring) {
            TourExplorerView(url: item.url)
        }
    }

    /// Keeps the tour's own top and bottom bars clear of the status bar, the "Explore tour" button
    /// and the slider's page indicator.
    private static let previewInsets = EdgeInsets(top: 60, leading: 0, bottom: 170, trailing: 0)

    private var poster: some View {
        ZStack {
            Color.black
            if let thumbnailURL = item.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
                .clipped()
            }
            if isActive && !isExploring {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
    }
}

/// Full-screen, interactive tour. The close control sits in its own bar above the page rather than
/// over it, so it never hides the provider's navigation.
private struct TourExplorerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var isLoaded = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Virtual tour", systemImage: "view.3d")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ZStack {
                TourWebView(
                    url: url,
                    isInteractive: true,
                    onLoaded: { isLoaded = true },
                    onFailed: { failure = $0 }
                )
                if let failure {
                    ContentUnavailableView("Tour unavailable", systemImage: "view.3d", description: Text(failure))
                        .foregroundStyle(.white)
                        .background(.black)
                } else if !isLoaded {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background(.black)
        .preferredColorScheme(.dark)
    }
}
