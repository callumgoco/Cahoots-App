import SwiftUI

struct ChallengeBuilderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var step = 0
    @State private var draft: ProposalDraft
    @State private var selectedTemplateID = "pushups"
    @State private var customName = ""
    @State private var isSubmitting = false
    @State private var showCloseConfirmation = false
    @State private var didLoad = false
    @FocusState private var focusedTargetField: TargetField?
    private let initialDraft: ProposalDraft?
    private let draftStore = ProposalDraftStore()
    private let stepTitles = ["Workout", "Target", "When", "Review"]
    private let totalSteps = 4

    init(initialDraft: ProposalDraft? = nil) {
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft ?? ProposalDraft())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    AdaptiveStack(spacing: AppSpacing.small) {
                        Text("Step \(step + 1) of \(totalSteps)").font(.caption.weight(.semibold)).foregroundStyle(AppColors.secondaryInk)
                        Spacer(minLength: 0)
                        Text(stepTitles[step]).font(.caption.bold())
                    }
                    ProgressView(value: Double(step + 1), total: Double(totalSteps)).tint(AppColors.accent)
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.small)

                Group {
                    switch step {
                    case 0: workoutStep
                    case 1: targetStep
                    case 2: whenStep
                    default: reviewStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: AppSpacing.small) {
                    if step < totalSteps - 1 {
                        AdaptiveStack(spacing: AppSpacing.small) {
                            if step > 0 { Button("Back") { step -= 1 }.buttonStyle(SecondaryButtonStyle()) }
                            Button("Continue") { step += 1 }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(!isStepValid || isSubmitting)
                                .accessibilityIdentifier("builder.continue")
                        }
                    } else {
                        Button {
                            Task { await startNow() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .tint(AppColors.onInk)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                            } else {
                                Text("Start now")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isStepValid || isSubmitting)
                        .accessibilityIdentifier("builder.startNow")
                        Text(firstCheckInAlreadyClosed
                             ? ScheduleEngine.firstCheckInClosedMessage
                             : VotingWindowCopy.startNowCaption(
                                startDate: draft.startDate,
                                timeZoneIdentifier: draft.timezone
                             ))
                        .font(.footnote)
                        .foregroundStyle(firstCheckInAlreadyClosed ? AppColors.danger : AppColors.secondaryInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(firstCheckInAlreadyClosed ? "builder.deadlinePassed" : "builder.startNowCaption")
                        Button {
                            Task { await putToVote() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            } else {
                                Text("Put to vote")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!isStepValid || isSubmitting || !canPutToVote)
                        .accessibilityIdentifier("builder.submit")
                        if canPutToVote {
                            Text(VotingWindowCopy.putToVoteCaption(closesAt: VotingWindowCopy.estimatedCloseDate()))
                                .font(.footnote)
                                .foregroundStyle(AppColors.secondaryInk)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("builder.putToVoteCaption")
                        } else {
                            Text(VotingWindowCopy.soloVoteDisabledHint)
                                .font(.footnote)
                                .foregroundStyle(AppColors.secondaryInk)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("builder.soloVoteHint")
                        }
                        if step > 0 {
                            Button("Back") { step -= 1 }
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                                .disabled(isSubmitting)
                        }
                    }
                }
                .cahootsSheetFooter()
            }
            .navigationTitle("New round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showCloseConfirmation = true }
                        .disabled(isSubmitting)
                }
            }
            .alert("Close this draft?", isPresented: $showCloseConfirmation) {
                Button("Keep draft") { saveDraft(); dismiss() }
                Button("Discard draft", role: .destructive) { clearDraft(); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your draft can be resumed for this group later.") }
            .roundPage()
            .interactiveKeyboardDismiss()
            .onAppear(perform: loadDraft)
            .onChange(of: draft) { _, _ in if didLoad { saveDraft() } }
        }
    }

    private var workoutStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("Choose a workout").font(.largeTitle.bold())
                LazyVStack(spacing: AppSpacing.small) {
                    ForEach(ActivityTemplate.all) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            AdaptiveStack(spacing: AppSpacing.medium) {
                                Image(systemName: template.symbol).font(.title2).frame(minWidth: 44, minHeight: 44)
                                VStack(alignment: .leading, spacing: AppSpacing.micro) {
                                    Text(template.displayName).font(.headline)
                                    Text(template.description).font(.caption).foregroundStyle(AppColors.secondaryInk)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: selectedTemplateID == template.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedTemplateID == template.id ? AppColors.accent : AppColors.secondaryInk)
                            }
                            .padding(AppSpacing.medium)
                            .environment(\.colorScheme, .dark)
                            .background(AppColors.raised, in: RoundedRectangle(cornerRadius: AppRadius.control))
                            .foregroundStyle(AppColors.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if selectedTemplateID == "custom" {
                    CahootsCard {
                        VStack(spacing: AppSpacing.medium) {
                            TextField("Activity name", text: $customName)
                                .onChange(of: customName) { _, value in draft.activityName = TextSanitizer.clean(value) }
                            Picker("Measurement", selection: $draft.measurementType) {
                                ForEach(MeasurementType.allCases) { Text($0.displayName.capitalized).tag($0) }
                            }
                        }
                    }
                }
            }
            .padding(AppSpacing.page)
        }
        .interactiveKeyboardDismiss()
    }

    private var targetStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text(targetStepHeadline).font(.largeTitle.bold())
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Daily target").font(.headline)
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                            TextField("Target", value: $draft.minimumQuantity, format: .number.precision(.fractionLength(0...1)))
                                .font(AppTypography.resultMetric)
                                .keyboardType(draft.measurementType == .distance ? .decimalPad : .numberPad)
                                .focused($focusedTargetField, equals: .quantity)
                                .accessibilityIdentifier("builder.target")
                            Image(systemName: "pencil")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppColors.secondaryInk)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, AppSpacing.medium)
                        .padding(.vertical, AppSpacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.raised, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .strokeBorder(
                                    AppColors.ink.opacity(focusedTargetField == .quantity ? 0.45 : 0.16),
                                    lineWidth: focusedTargetField == .quantity ? 1.5 : 1
                                )
                        )
                        Text(draft.measurementType.displayName).foregroundStyle(AppColors.secondaryInk)
                        AdaptiveStack(spacing: AppSpacing.small) {
                            ForEach(suggestedTargets, id: \.self) { target in
                                let isSelected = draft.minimumQuantity == target
                                Button(target.formatted()) { draft.minimumQuantity = target }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isSelected ? AppColors.onInk : AppColors.ink)
                                    .padding(.horizontal, AppSpacing.medium)
                                    .frame(minHeight: 36)
                                    .background(
                                        isSelected ? AppColors.ink : AppColors.raised,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(AppColors.ink.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                CahootsField(title: "Challenge title", isFocused: focusedTargetField == .title) {
                    HStack(spacing: AppSpacing.small) {
                        TextField(
                            "",
                            text: $draft.title,
                            prompt: Text("Name this round").foregroundStyle(AppColors.secondaryInk)
                        )
                        .textInputAutocapitalization(.words)
                        .focused($focusedTargetField, equals: .title)
                        .accessibilityIdentifier("builder.title")
                        Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryInk)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(AppSpacing.page)
        }
        .interactiveKeyboardDismiss()
    }

    private var whenStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("When do you check in?").font(.largeTitle.bold())
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Schedule").font(.headline)
                        Picker("Schedule", selection: $draft.frequencyType) {
                            Text("Every day").tag(FrequencyType.daily)
                            Text("Selected days").tag(FrequencyType.selectedWeekdays)
                        }
                        .pickerStyle(.segmented)
                        if draft.frequencyType == .selectedWeekdays {
                            ForEach(1...7, id: \.self) { day in
                                Toggle(weekdayName(day), isOn: weekdayBinding(day))
                            }
                        }
                    }
                }
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Length").font(.headline)
                        Stepper("\(draft.durationDays) days", value: $draft.durationDays, in: 7...90)
                        DatePicker("Starts", selection: $draft.startDate, in: store.earliestProposalStartDate..., displayedComponents: .date)
                        if firstCheckInAlreadyClosed {
                            Text(ScheduleEngine.firstCheckInClosedMessage)
                                .font(.footnote)
                                .foregroundStyle(AppColors.danger)
                                .accessibilityIdentifier("builder.deadlinePassed")
                        }
                    }
                }
                CahootsCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Check-in rules").font(.headline)
                        Text("Daily deadline")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.secondaryInk)
                        SlidingTimeDial(minutesFromMidnight: $draft.deadlineMinutes)
                            .padding(.bottom, AppSpacing.medium)
                        Picker("Timezone", selection: $draft.timezone) {
                            ForEach(timezoneOptions, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                        }
                        Stepper("\(draft.recoveryDays) recovery \(draft.recoveryDays == 1 ? "day" : "days")", value: $draft.recoveryDays, in: 0...4)
                    }
                }
                Text("Members record their own check-ins. Recovery protects a streak and awards no points.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.secondaryInk)
            }
            .padding(AppSpacing.page)
            .padding(.bottom, AppSpacing.extraLarge + AppSpacing.large)
        }
        .onChange(of: draft.frequencyType) { _, value in if value == .daily { draft.scheduledWeekdays = Set(1...7) } }
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("Ready to go").font(.largeTitle.bold())
                CahootsCard(elevated: true) {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        StatusPill(
                            text: canPutToVote ? "Start now or put to vote" : "Start now",
                            kind: .positive
                        )
                        Text(draft.title).font(.title.bold())
                        AdaptiveStack(spacing: AppSpacing.small) {
                            Text(draft.minimumQuantity.formatted()).font(AppTypography.heroMetric)
                            Text(draft.measurementType.displayName).font(.title3.bold())
                        }
                        Divider()
                        Label(scheduleSummary, systemImage: "calendar")
                        Label("\(draft.durationDays) days from \(draft.startDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "flag.checkered")
                        Label("Daily check-in closes \(deadlineText) · \(draft.timezone)", systemImage: "clock")
                        Label("\(draft.recoveryDays) recovery \(draft.recoveryDays == 1 ? "day" : "days")", systemImage: "moon.zzz")
                    }
                }
                Text(VotingWindowCopy.reviewFootnote(
                    canPutToVote: canPutToVote,
                    closesAt: VotingWindowCopy.estimatedCloseDate()
                ))
                    .font(.footnote)
                    .foregroundStyle(AppColors.secondaryInk)
            }
            .padding(AppSpacing.page)
        }
    }

    private var canPutToVote: Bool {
        store.groupMembers.count >= 2
    }

    private var isStepValid: Bool {
        switch step {
        case 0:
            selectedTemplateID != "custom" || TextSanitizer.clean(customName).count >= 2
        case 1:
            draft.minimumQuantity > 0 && TextSanitizer.clean(draft.title).count >= 2
        case 2:
            !draft.scheduledWeekdays.isEmpty
                && (7...90).contains(draft.durationDays)
                && draft.startDate >= store.earliestProposalStartDate
                && (0..<1_440).contains(draft.deadlineMinutes)
                && TimeZone(identifier: draft.timezone) != nil
                && (0...4).contains(draft.recoveryDays)
                && !firstCheckInAlreadyClosed
        default:
            !firstCheckInAlreadyClosed
        }
    }

    private var firstCheckInAlreadyClosed: Bool {
        ScheduleEngine.firstCheckInAlreadyClosed(
            startDate: draft.startDate,
            deadlineMinutes: draft.deadlineMinutes,
            timeZoneIdentifier: draft.timezone,
            frequencyType: draft.frequencyType,
            scheduledWeekdays: draft.scheduledWeekdays,
            now: store.environment.clock.now
        )
    }

    private var targetStepHeadline: String {
        switch draft.measurementType {
        case .repetitions: String(localized: "How many reps?")
        case .seconds, .minutes: String(localized: "How long?")
        case .distance: String(localized: "How far?")
        }
    }

    private var suggestedTargets: [Double] {
        switch draft.measurementType {
        case .repetitions: [10, 15, 20]
        case .seconds: [20, 30, 45]
        case .minutes: [10, 15, 20]
        case .distance: [1, 2, 3]
        }
    }

    private var timezoneOptions: [String] {
        Array(Set([TimeZone.current.identifier, "Europe/London", "America/New_York", "America/Los_Angeles", "Asia/Kolkata", "Australia/Sydney"])).sorted()
    }

    private var deadlineBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: draft.deadlineMinutes / 60, minute: draft.deadlineMinutes % 60, second: 0, of: .now) ?? .now
        } set: { value in
            let components = Calendar.current.dateComponents([.hour, .minute], from: value)
            draft.deadlineMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    private var deadlineText: String { deadlineBinding.wrappedValue.formatted(date: .omitted, time: .shortened) }
    private var scheduleSummary: String {
        draft.frequencyType == .daily
            ? String(localized: "Every day")
            : draft.scheduledWeekdays.sorted().map(weekdayName).joined(separator: ", ")
    }

    private func weekdayName(_ day: Int) -> String { Calendar.current.weekdaySymbols[max(0, min(6, day - 1))] }
    private func weekdayBinding(_ day: Int) -> Binding<Bool> {
        Binding(get: { draft.scheduledWeekdays.contains(day) }, set: { enabled in
            if enabled { draft.scheduledWeekdays.insert(day) } else { draft.scheduledWeekdays.remove(day) }
        })
    }

    private func generatedTitle(_ activity: String) -> String {
        "\(draft.durationDays)-Day \(activity.replacingOccurrences(of: " · time", with: "").replacingOccurrences(of: " · distance", with: "")) Challenge"
    }

    private func applyTemplate(_ template: ActivityTemplate) {
        selectedTemplateID = template.id
        draft.activityName = template.activityName
        draft.measurementType = template.measurementType
        draft.minimumQuantity = template.suggestedTarget
        if template.id != "custom" { draft.title = generatedTitle(template.displayName) }
    }

    private func loadDraft() {
        guard !didLoad else { return }
        if initialDraft == nil,
           let userID = store.currentUser?.id,
           let groupID = store.currentGroup?.id,
           let saved = draftStore.load(userID: userID, groupID: groupID) {
            draft = saved
        }
        draft.startDate = max(draft.startDate, store.earliestProposalStartDate)
        if let match = ActivityTemplate.all.first(where: { $0.activityName == draft.activityName }) {
            selectedTemplateID = match.id
        } else if draft.activityName != "push-ups" {
            selectedTemplateID = "custom"
            customName = draft.activityName
        }
        didLoad = true
        saveDraft()
    }

    private func saveDraft() {
        guard let userID = store.currentUser?.id, let groupID = store.currentGroup?.id else { return }
        draftStore.save(draft, userID: userID, groupID: groupID)
    }

    private func clearDraft() {
        guard let userID = store.currentUser?.id, let groupID = store.currentGroup?.id else { return }
        draftStore.clear(userID: userID, groupID: groupID)
    }

    private func startNow() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if await store.startChallenge(from: draft) { clearDraft(); dismiss() }
    }

    private func putToVote() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if await store.createProposal(from: draft) { clearDraft(); dismiss() }
    }

    private enum TargetField: Hashable {
        case quantity
        case title
    }
}
