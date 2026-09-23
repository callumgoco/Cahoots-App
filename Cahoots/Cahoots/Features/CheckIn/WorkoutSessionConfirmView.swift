import SwiftUI

struct WorkoutSessionConfirmView: View {
    @Bindable var controller: WorkoutSessionController
    let store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var amountIsFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 88
    @ScaledMetric(relativeTo: .largeTitle) private var accessibilityAmountSize: CGFloat = 56

    var body: some View {
        ZStack {
            confirmBackdrop

            VStack(spacing: 0) {
                ScrollView {
                    CahootsCard(elevated: true) {
                        VStack(spacing: AppSpacing.extraLarge) {
                            if let challenge = store.currentChallenge {
                                VStack(spacing: AppSpacing.micro) {
                                    Text("Today’s amount")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppColors.secondaryInk)
                                    TextField("0", value: $controller.amount, format: .number.precision(.fractionLength(0...1)))
                                        .font(
                                            .system(
                                                size: dynamicTypeSize.isAccessibilitySize ? accessibilityAmountSize : amountSize,
                                                weight: .heavy,
                                                design: .rounded
                                            )
                                        )
                                        .monospacedDigit()
                                        .multilineTextAlignment(.center)
                                        .keyboardType(challenge.measurementType == .distance ? .decimalPad : .numberPad)
                                        .focused($amountIsFocused)
                                        .accessibilityLabel("Completed quantity in \(challenge.measurementType.displayName)")
                                        .accessibilityIdentifier("checkIn.amount")
                                    Text(challenge.measurementType.displayName)
                                        .font(.title2.bold())
                                        .foregroundStyle(AppColors.secondaryInk)
                                }

                                HStack(spacing: AppSpacing.small) {
                                    incrementButton("−1", change: -1)
                                    incrementButton("+1", change: 1)
                                    incrementButton("+5", change: 5)
                                }

                                if controller.amount >= challenge.minimumQuantity {
                                    Text("+\(ScoringEngine.points(completedQuantity: controller.amount, minimumQuantity: challenge.minimumQuantity)) points if you finish")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppColors.accent)
                                }
                            }
                            if let formError = controller.formError {
                                Label(formError, systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(AppColors.danger)
                                    .font(.body.weight(.semibold))
                            }
                            if controller.recordedClips.isEmpty {
                                Label("Logging the number only — the crew won’t get a video. This round is honour system.", systemImage: "hand.raised.fill")
                                    .font(.footnote)
                                    .foregroundStyle(AppColors.secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Label("A short clip for the crew. You enter the number — this round is honour system.", systemImage: "hand.raised.fill")
                                    .font(.footnote)
                                    .foregroundStyle(AppColors.secondaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(AppSpacing.page)
                    .padding(.top, AppSpacing.large)
                }
                .interactiveKeyboardDismiss()

                Button {
                    controller.requestSubmit(store: store)
                } label: {
                    if controller.isSubmitting {
                        ProgressView()
                            .tint(AppColors.onInk)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        Text(controller.amount >= (store.currentChallenge?.minimumQuantity ?? 0) ? "Complete check-in" : "Save progress")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    controller.amount <= 0
                        || controller.isSubmitting
                        || !controller.openedWhileWindowOpen
                        || !WorkoutClipRules.areSubmittable(controller.recordedClips, for: store.currentChallenge?.measurementType ?? .repetitions)
                )
                .accessibilityIdentifier("checkIn.submit")
                .cahootsSheetFooter()
            }
        }
        .interactiveKeyboardDismiss()
        .onAppear {
            controller.ensureClosedWindowErrorIfNeeded()
        }
    }

    private var confirmBackdrop: some View {
        ZStack {
            AppColors.page.ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func incrementButton(_ title: String, change: Double) -> some View {
        Button(title) { controller.adjustAmount(change) }
            .font(.title2.bold().monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(AppColors.ink)
            .environment(\.colorScheme, .dark)
            .background(AppColors.raised, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }
}
