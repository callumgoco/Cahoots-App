import SwiftUI

struct WorkoutSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var controller = WorkoutSessionController()

    var body: some View {
        @Bindable var controller = controller
        NavigationStack {
            ZStack {
                if controller.keepsCameraMounted {
                    cameraBackground
                }
                phaseContent
            }
            .navigationTitle(controller.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(controller.showsCameraPreview ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(AppColors.page, for: .navigationBar)
            .toolbarColorScheme(controller.showsCameraPreview ? .dark : nil, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(controller.dismissLabel) { close() }
                        .disabled(controller.isSubmitting || controller.isActivelyRecording)
                }
            }
        }
        .interactiveDismissDisabled(controller.isSubmitting || controller.isActivelyRecording || controller.submittedPoints != nil)
        .onAppear { controller.bootstrap(store: store) }
        .onDisappear { controller.tearDown() }
        .alert("That’s much higher than the target", isPresented: $controller.showHighConfirmation) {
            Button("Submit anyway") { Task { await controller.submit(store: store) } }
            Button("Review amount", role: .cancel) {}
        } message: {
            Text("Check that the quantity and unit are correct. Bonus points remain capped at 10.")
        }
        .sensoryFeedback(.success, trigger: controller.submittedPoints)
    }

    @ViewBuilder
    private var cameraBackground: some View {
        CameraPreviewRepresentable(session: controller.captureSession, position: controller.cameraPosition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        if controller.usesStubCapture {
            Color.black.opacity(0.85).ignoresSafeArea()
            Text("Camera preview (stub)")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .accessibilityLabel(String(localized: "Camera preview unavailable. Using stub camera."))
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .choose:
            WorkoutSessionChooseView(controller: controller, store: store)
        case .prep:
            WorkoutSessionPrepView(controller: controller, store: store, reduceMotion: reduceMotion)
        case .countdown(let value):
            WorkoutSessionCountdownOverlay(value: value)
        case .record:
            WorkoutSessionRecordView(controller: controller)
        case .review, .waitingForFinish:
            WorkoutSessionReviewView(controller: controller, store: store)
        case .confirm:
            WorkoutSessionConfirmView(controller: controller, store: store)
        case .reveal:
            WorkoutSessionRevealView(controller: controller, store: store, onDone: close)
        case .permissionDenied:
            WorkoutSessionPermissionView(controller: controller)
        }
    }

    private func close() {
        controller.close(store: store)
        dismiss()
    }
}
