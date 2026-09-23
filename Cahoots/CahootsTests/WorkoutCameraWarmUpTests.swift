import Foundation
import Testing
@testable import Cahoots

@Suite(.serialized)
@MainActor
struct WorkoutCameraWarmUpTests {
    @Test func concurrentPrepareReusesSingleCaptureSession() async {
        let stub = StubWorkoutCaptureController()
        stub.prepareDelayNanoseconds = 80_000_000

        let controller = WorkoutSessionController()
        controller.captureFactory = { stub }
        controller.openedWhileWindowOpen = true

        async let first: Void = controller.prepareCapture()
        async let second: Void = controller.prepareCapture()
        _ = await (first, second)

        #expect(controller.isCaptureReady)
        #expect(stub.prepareCallCount == 1)
        #expect((controller.capture as? StubWorkoutCaptureController) === stub)
    }

    @Test func secondPrepareWhileReadyDoesNotRebuildCapture() async {
        let stub = StubWorkoutCaptureController()

        let controller = WorkoutSessionController()
        controller.captureFactory = { stub }
        controller.openedWhileWindowOpen = true

        await controller.prepareCapture()
        #expect(stub.prepareCallCount == 1)
        #expect(controller.isCaptureReady)

        await controller.prepareCapture()
        #expect(stub.prepareCallCount == 1)
    }

    @Test func skipRecordingTearsDownWarmedCapture() async {
        let stub = StubWorkoutCaptureController()

        let controller = WorkoutSessionController()
        controller.captureFactory = { stub }
        controller.openedWhileWindowOpen = true
        await controller.prepareCapture()
        #expect(controller.capture != nil)
        #expect(controller.isCaptureReady)

        controller.skipRecording()
        #expect(controller.capture == nil)
        #expect(controller.isCaptureReady == false)
        #expect(controller.phase == .confirm)
    }

    @Test func warmUpWhileWindowClosedDoesNothing() async {
        let stub = StubWorkoutCaptureController()

        let controller = WorkoutSessionController()
        controller.captureFactory = { stub }
        controller.openedWhileWindowOpen = false
        controller.beginCameraWarmUpIfNeeded()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(stub.prepareCallCount == 0)
        #expect(controller.capture == nil)
    }
}
