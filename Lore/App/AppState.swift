import Foundation
import SwiftData
import Observation

@MainActor @Observable final class AppState {
    let folders = FolderAccessController()
    let closedLid = ClosedLidController()
    let lidValidation = ClosedLidValidation()
    let loginItem = LoginItemController()
    let updates = AppUpdateController()
    let notch: NotchController
    let pulse: PulseController
    let preferences = LorePreferences.shared
    var destination: Destination = .today
    var selectedProjectID: String?
    var isIndexing = false
    var progress: IndexingProgress?
    var report: IndexingReport?
    var lastIndexedAt: Date?
    var errorMessage: String?
    var revision = 0
    @ObservationIgnored var openSupportPage: (() -> Void)?
    @ObservationIgnored private let worker: IndexingWorker
    @ObservationIgnored private var activeIndex: Task<IndexingReport, any Error>?
    @ObservationIgnored private var started = false
    init(container: ModelContainer) {
        worker = IndexingWorker(container: container, cacheURL: SessionIndexCache.defaultURL)
        notch = NotchController(closedLid: closedLid)
        pulse = PulseController(notch: notch)
        notch.pulse = pulse
    }
    func start() async {
        guard !started else { return }
        started = true
        await notch.configureSources(folders.integrations)
        notch.start()
        await closedLid.refresh()
        await refresh()
    }
    func accessChanged() async {
        await notch.configureSources(folders.integrations)
        await refresh()
    }
    func refresh() async {
        guard !isIndexing else { return }
        isIndexing = true; errorMessage = nil
        progress = IndexingProgress(message: "Discovering local sessions", completed: 0, total: 0)
        defer { isIndexing = false; progress = nil; activeIndex = nil }
        await worker.configure(integrations: folders.integrations, repositoryAccess: folders.repositoryPolicy)
        let observer: @Sendable (IndexingProgress) -> Void = { [weak self] update in
            guard let owner = self else { return }
            Task { @MainActor in if owner.isIndexing { owner.progress = update } }
        }
        let job = Task { [worker] in try await worker.index(progress: observer) }
        activeIndex = job
        do {
            report = try await job.value; lastIndexedAt = .now; revision += 1
        } catch is CancellationError {
            errorMessage = "Refresh cancelled. Saved history is unchanged."
        } catch {
            errorMessage = "Refresh could not finish. Saved history is available; review folder access in Settings."
        }
    }
    func cancelRefresh() { activeIndex?.cancel() }
}
