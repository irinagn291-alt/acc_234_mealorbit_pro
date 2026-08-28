import SwiftUI

struct OrbitCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(OrbitSpace.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
    }
}

struct PayloadThumb: View {
    let payload: OrbitPayload
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let remote = payload.imageURL, let url = URL(string: remote) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        bundledOrPlaceholder
                    case .empty:
                        OrbitPalette.color(.surface)
                            .overlay(ProgressView().opacity(0))
                    @unknown default:
                        bundledOrPlaceholder
                    }
                }
            } else {
                bundledOrPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: OrbitSpace.radius))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var bundledOrPlaceholder: some View {
        if let bundled = payload.bundledAsset {
            Image(bundled)
                .resizable()
                .scaledToFill()
        } else {
            Image("mlo_ProductPlaceholder")
                .resizable()
                .scaledToFill()
        }
    }
}

struct OrbitEmptyState: View {
    let image: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: OrbitSpace.stack) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .accessibilityHidden(true)
            Text(title)
                .font(OrbitType.title.font)
                .foregroundStyle(OrbitPalette.color(.ink))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(OrbitType.body.font)
                .foregroundStyle(OrbitPalette.color(.muted))
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(actionTitle)
                    .font(OrbitType.body.font)
                    .frame(minWidth: 160, minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.background))
                    .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
            }
            .accessibilityLabel(actionTitle)
        }
        .padding(OrbitSpace.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OrbitErrorState: View {
    let title: String
    let detail: String
    let retryTitle: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: OrbitSpace.stack) {
            Image("mlo_EmptySearch")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
                .accessibilityHidden(true)
            Text(title)
                .font(OrbitType.title.font)
                .foregroundStyle(OrbitPalette.color(.ink))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(OrbitType.body.font)
                .foregroundStyle(OrbitPalette.color(.muted))
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text(retryTitle)
                    .font(OrbitType.body.font)
                    .frame(minWidth: 160, minHeight: OrbitSpace.tap)
                    .foregroundStyle(OrbitPalette.color(.background))
                    .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
            }
            .accessibilityLabel(retryTitle)
        }
        .padding(OrbitSpace.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VaultFaultView: View {
    let message: String

    var body: some View {
        ZStack {
            OrbitPalette.color(.background).ignoresSafeArea()
            VStack(spacing: OrbitSpace.stack) {
                Image("mlo_EmptyPlan")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .accessibilityHidden(true)
                Text("Vault offline")
                    .font(OrbitType.title.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                Text(message)
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                    .multilineTextAlignment(.center)
            }
            .padding(OrbitSpace.inset)
        }
    }
}

struct PasscodeLockView: View {
    let expected: String
    let onUnlock: () -> Void
    @State private var draft = ""
    @State private var failed = false

    var body: some View {
        ZStack {
            OrbitPalette.color(.background).ignoresSafeArea()
            VStack(spacing: OrbitSpace.stack) {
                Image("mlo_ControlFace")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Airlock")
                    .font(OrbitType.title.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                Text("Enter the local passcode to open the deck.")
                    .font(OrbitType.body.font)
                    .foregroundStyle(OrbitPalette.color(.muted))
                    .multilineTextAlignment(.center)
                SecureField("Passcode", text: $draft)
                    .textContentType(.password)
                    .font(OrbitType.figure.font)
                    .foregroundStyle(OrbitPalette.color(.ink))
                    .padding(OrbitSpace.inset)
                    .frame(minHeight: OrbitSpace.tap)
                    .background(OrbitPalette.color(.surface), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                    .accessibilityLabel("Local passcode")
                if failed {
                    Text("That code does not match.")
                        .font(OrbitType.caption.font)
                        .foregroundStyle(OrbitPalette.color(.muted))
                }
                Button("Unlock") {
                    if draft == expected {
                        onUnlock()
                    } else {
                        failed = true
                    }
                }
                .font(OrbitType.body.font)
                .frame(maxWidth: .infinity, minHeight: OrbitSpace.tap)
                .foregroundStyle(OrbitPalette.color(.background))
                .background(OrbitPalette.color(.accent), in: RoundedRectangle(cornerRadius: OrbitSpace.radius))
                .accessibilityLabel("Unlock")
            }
            .padding(OrbitSpace.inset)
        }
    }
}

struct TextureBackdrop: View {
    var body: some View {
        ZStack {
            OrbitPalette.color(.background)
            Image("mlo_Texture")
                .resizable(resizingMode: .tile)
                .opacity(0.18)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

struct StaggerRow<Content: View>: View {
    let index: Int
    let highlighted: Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        content()
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: OrbitSpace.radius)
                        .stroke(OrbitPalette.color(.accent), lineWidth: 2)
                }
            }
            .onAppear {
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(OrbitMotion.curve.delay(Double(index) * 0.05)) {
                        visible = true
                    }
                }
            }
    }
}
