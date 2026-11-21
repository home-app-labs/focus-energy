import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// A QR code drawn crisp at any size.
struct QRCode: View {
    let text: String
    var side: CGFloat = 132

    var body: some View {
        Group {
            if let image = Self.image(text) {
                Image(nsImage: image).interpolation(.none).resizable()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: side, height: side)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
    }

    static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// Three steps to get timer notifications on the phone.
struct PhoneSetupView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var push: PhonePush
    @State private var copied = false

    static let appStore = "https://apps.apple.com/app/ntfy/id1625396347"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications on your phone").font(.title2.weight(.semibold))
                Text("Three steps, about two minutes. No account is needed.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            step(1, "Get the ntfy app", tint: Palette.start) {
                HStack(alignment: .top, spacing: 16) {
                    QRCode(text: Self.appStore)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Point the iPhone camera at this code and tap the link.")
                        Text("The App Store opens on the free app \"ntfy\". Install it, open it and allow notifications.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            step(2, "Subscribe to your topic", tint: Palette.ringFocus) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In ntfy tap **+** in the top right corner, enter this topic name and tap **Subscribe**.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Text(settings.pushTopic)
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.pushTopic, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        }
                    }
                    Text("No need to type: press Copy here, then paste on the iPhone. The clipboard is shared between your Apple devices.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            step(3, "Check the connection", tint: Palette.rest) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Send a test, then press **It works** in the notification on the phone. If there is no button, press and hold the notification.")
                    HStack(spacing: 12) {
                        Button("Send a test") { push.sendTest() }
                            .buttonStyle(.borderedProminent).tint(Palette.start)
                        status
                    }
                }
            }

            HStack {
                Text("The topic name works like a password. Do not share it.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear {
            if settings.pushTopic.isEmpty { settings.regeneratePushTopic() }
            if !settings.pushEnabled { settings.pushEnabled = true }
        }
    }

    @ViewBuilder private var status: some View {
        if push.confirmedAt != nil {
            Label("Phone connected. Everything works.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.rest).fontWeight(.semibold)
        } else {
            switch push.sendStatus {
            case .idle: EmptyView()
            case .sending: Text("Sending…").foregroundStyle(.secondary)
            case .sent:
                Label("Sent. Waiting for \"It works\" from the phone…", systemImage: "paperplane.fill")
                    .foregroundStyle(.secondary)
            case .failed(let reason):
                Label("Not sent: \(reason)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.focus)
            }
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, tint: Color,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
    }
}
