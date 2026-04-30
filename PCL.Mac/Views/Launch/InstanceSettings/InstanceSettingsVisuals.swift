import SwiftUI
import AppKit
import Core

struct InstanceSettingsBackground<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.color5.opacity(0.55), Color.color7.opacity(0.88), Color.color8],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            content
        }
    }
}

struct InstanceSettingsScrollPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        InstanceSettingsBackground {
            ScrollView {
                VStack(spacing: 12) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
    }
}

struct InstanceSettingsHeaderCard: View {
    let instance: MinecraftInstance
    let subtitle: String?

    var body: some View {
        MyCard("", foldable: false, titled: false, padding: 14) {
            HStack(spacing: 10) {
                Image(instance.modLoader?.icon ?? "GrassBlock")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    MyText(instance.name, size: 14)
                    MyText(subtitle ?? instance.version.description, size: 11.5, color: .colorGray3)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct InstanceSettingsInfoBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.color3)
                .frame(width: 2)
            MyText(text, size: 12, color: .color3)
            Spacer(minLength: 0)
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.color3.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.color6.opacity(0.65))
        )
    }
}

struct InstanceSettingsSectionCard<Content: View>: View {
    let title: String
    let folded: Bool?
    private let content: Content

    init(_ title: String, folded: Bool? = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.folded = folded
        self.content = content()
    }

    var body: some View {
        MyCard(title, foldable: true, folded: folded, padding: 14) {
            content
        }
    }
}

struct InstanceSettingsFieldRow<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 14) {
            MyText(label, size: 12)
                .frame(width: 98, alignment: .leading)
            content
        }
    }
}

struct InstanceSettingsCheckboxRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isOn ? Color.color3 : Color.colorGray2)
                MyText(title, size: 12, color: .color1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InstanceSettingsRadioRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(selected ? Color.color3 : Color.colorGray2)
                MyText(title, size: 12, color: .color1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InstanceSettingsInputBox: View {
    let text: String
    var placeholder: Bool = false
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            MyText(text, size: 12, color: placeholder ? .colorGray3 : .color1)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.colorGray3)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.color6, lineWidth: 1)
                )
        )
    }
}

struct InstanceSettingsCenterActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                    Text(title)
                        .font(.custom("PCLEnglish", size: 14))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(
                    Capsule()
                        .fill(Color.color3)
                        .shadow(color: Color.black.opacity(0.16), radius: 6, y: 2)
                )
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }
}

struct InstanceSettingsFloatingActionButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: action) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color.color3)
                                .shadow(color: Color.black.opacity(0.16), radius: 6, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
    }
}

struct InstanceSettingsEmptyStateCard: View {
    let title: String
    let description: String
    let primaryTitle: String
    let secondaryTitle: String?
    let primaryAction: () -> Void
    let secondaryAction: (() -> Void)?

    var body: some View {
        VStack {
            Spacer()
            MyCard("", foldable: false, titled: false, padding: 18) {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        MyText(title, size: 18, color: .color3)
                        Rectangle()
                            .fill(Color.color3)
                            .frame(height: 2)
                        MyText(description, size: 12, color: .colorGray2)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 14) {
                        MyButton(primaryTitle) { primaryAction() }
                            .frame(width: 112)
                        if let secondaryTitle, let secondaryAction {
                            MyButton(secondaryTitle) { secondaryAction() }
                                .frame(width: 112)
                        }
                    }
                    .frame(height: 35)
                }
                .frame(width: 280)
            }
            Spacer()
        }
    }
}

struct InstanceSettingsLocalImage: View {
    let url: URL
    let size: CGSize
    let cornerRadius: CGFloat
    let fallbackIcon: String

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(fallbackIcon)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .foregroundStyle(Color.colorGray3)
                    .background(Color.colorGray8.opacity(0.8))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
