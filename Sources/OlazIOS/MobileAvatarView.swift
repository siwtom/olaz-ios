import SwiftUI

struct MobileAvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44
    var isGroup: Bool = false

    @State private var loadedImage: PlatformImage?

    var body: some View {
        Group {
            if let image = cachedOrLoaded {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if isGroup && name.isEmpty {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text(nameInitials(name))
                            .font(.system(size: max(11, size * 0.36), weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .task(id: url) {
            loadedImage = nil
            guard let url else { return }
            let px = min(300, max(96, size * 3))
            if let hit = MediaLoader.cachedImage(for: url, maxPixelSize: px) {
                loadedImage = hit
                return
            }
            if let fetched = await MediaLoader.shared.image(for: url, maxPixelSize: px) {
                loadedImage = fetched.image
            }
        }
    }

    private var cachedOrLoaded: PlatformImage? {
        if let loadedImage { return loadedImage }
        guard let url else { return nil }
        return MediaLoader.cachedImage(for: url, maxPixelSize: min(300, max(96, size * 3)))
    }

    private var gradientColors: [Color] {
        let palette: [[Color]] = [
            [Color(hex: "#0068FF") ?? .blue, Color(hex: "#3A8DFF") ?? .cyan],
            [Color(hex: "#00A88F") ?? .teal, Color(hex: "#2AC5BB") ?? .mint],
            [Color(hex: "#6F3FCF") ?? .purple, Color(hex: "#9B6DF0") ?? .indigo],
            [Color(hex: "#F26B3A") ?? .orange, Color(hex: "#FF9248") ?? .yellow],
        ]
        let hash = abs(name.unicodeScalars.reduce(0) { $0 * 31 + Int($1.value) })
        return palette[hash % palette.count]
    }
}
