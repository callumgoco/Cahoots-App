import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct InviteShareView: View {
    let group: CahootsGroup
    let invite: GroupInvite
    let done: () -> Void
    @State private var copied = false

    private var link: String { "https://\(AppIdentity.inviteHost)/join/\(invite.code)" }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                VStack(spacing: AppSpacing.small) {
                    Text(group.emoji).font(.system(size: 56))
                    Text("Invite friends to \(group.name)").font(.title.bold()).multilineTextAlignment(.center)
                    Text("Anyone with this code can join this group until it expires.").foregroundStyle(AppColors.secondaryInk).multilineTextAlignment(.center)
                }
                CahootsCard(elevated: true) {
                    VStack(spacing: AppSpacing.medium) {
                        QRCodeView(text: link).frame(width: 164, height: 164)
                        Text(invite.code).font(.system(size: 36, weight: .heavy, design: .rounded).monospaced())
                        Text("Expires \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(AppColors.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                }
                AdaptiveStack(spacing: AppSpacing.small) {
                    Button(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = invite.code
                        copied = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    ShareLink(item: link, subject: Text("Join \(group.name) on \(AppIdentity.name)"), message: Text("Use code \(invite.code) to join our private workout challenge.")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Button("Done", action: done)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("invite.done")
                    .padding(.top, AppSpacing.small)
            }
            .padding(AppSpacing.page)
        }
        .roundPage()
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = makeImage() {
            Image(uiImage: image).interpolation(.none).resizable().accessibilityLabel("Invitation QR code")
        } else {
            Image(systemName: "qrcode").resizable().accessibilityLabel("QR code unavailable")
        }
    }

    private func makeImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
