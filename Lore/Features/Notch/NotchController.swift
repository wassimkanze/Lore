import SwiftUI
import AppKit
import Observation

private final class ActivityPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Lore — live agents"
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        alphaValue = 1; colorSpace = .sRGB
        isFloatingPanel = true; hidesOnDeactivate = false; isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false; animationBehavior = .none; acceptsMouseMovedEvents = true
    }
}

@MainActor @Observable final class NotchController {
    static let powerID = "__keep_awake"
    static let agentsID = "__all_agents"
    let keepAwake = KeepAwakeController()
    let closedLid: ClosedLidController
    @ObservationIgnored weak var pulse: PulseController?
    @ObservationIgnored var openPulsePage: (() -> Void)?
    private(set) var isEnabled: Bool
    private(set) var announcementsEnabled: Bool
    private(set) var sessions: [LiveSession] = []
    private(set) var experience = NotchExperience()
    private(set) var unreadableFiles = 0
    private(set) var usesNotch = false
    private(set) var selectedID: String?
    private(set) var isExpanded = false
    private(set) var isPinned = false
    private(set) var showsDetails = false
    private(set) var contentVisible = false
    private(set) var announcement: NotchAnnouncement?
    var activitySummary: LiveActivitySummary { experience.indicator }
    var groups: [LiveProviderGroup] { experience.groups }
    var pendingRowCount: Int { experience.pendingRowCount }
    var attentionSession: LiveSession? { experience.attention.first }
    var powerStatus: String {
        if closedLid.restorationPending { return "Checking sleep restoration…" }
        if closedLid.isActive { return "Closed-lid mode · \(max(1, Int(ceil(closedLid.secondsRemaining / 60)))) min remaining" }
        guard keepAwake.isActive else { return "Normal sleep allowed" }
        if keepAwake.policy.mode == .untilTasksFinish { return "Mac awake · until tasks finish" }
        let now = experience.now == .distantPast ? Date.now : experience.now
        let minutes = max(1, Int(ceil((keepAwake.policy.deadline ?? now).timeIntervalSince(now) / 60)))
        return "Mac awake · \(minutes) min remaining"
    }
    @ObservationIgnored private let monitor = LiveActivityMonitor()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var expandTask: Task<Void, Never>?
    @ObservationIgnored private var contentTask: Task<Void, Never>?
    @ObservationIgnored private var announcementTask: Task<Void, Never>?
    @ObservationIgnored private var panels: [ActivityPanel] = []
    @ObservationIgnored private var expandedPanel: ActivityPanel?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var pointerInsidePanel = false
    @ObservationIgnored private var automaticPresentation = false
    @ObservationIgnored private var isDismissing = false
    @ObservationIgnored private var powerContentHeight: CGFloat = 150
    @ObservationIgnored private let rendersPanels: Bool
    private static let preference = "liveNotchEnabled"
    private static let announcementsPreference = "notchBriefUpdatesEnabled"
    init(closedLid: ClosedLidController = ClosedLidController(), rendersPanels: Bool = true) {
        self.closedLid = closedLid
        self.rendersPanels = rendersPanels
        isEnabled = UserDefaults.standard.object(forKey: Self.preference) as? Bool ?? true
        announcementsEnabled = UserDefaults.standard.object(forKey: Self.announcementsPreference) as? Bool ?? true
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.render() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.keepAwake.stop() }
        })
    }
    func configureSources(_ integrations: [any AIProviderIntegration]) async {
        experience.suppressNextAnnouncements()
        await monitor.configure(integrations: integrations)
    }
    func start() {
        guard task == nil, !suspended else { return }
        render()
        task = Task { [weak self, monitor] in
            while !Task.isCancelled {
                let snapshot = await monitor.poll()
                guard !Task.isCancelled else { break }
                self?.receive(snapshot)
                do { try await Task.sleep(for: .seconds(LiveActivityPolicy.pollingInterval)) }
                catch { break }
            }
        }
    }
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled; UserDefaults.standard.set(enabled, forKey: Self.preference)
        if enabled { start(); render() }
        else { hideAll() }
    }
    func setAnnouncementsEnabled(_ enabled: Bool) {
        announcementsEnabled = enabled; UserDefaults.standard.set(enabled, forKey: Self.announcementsPreference)
        if !enabled && automaticPresentation { dismiss() }
    }
    func choosePower(_ mode: KeepAwakeMode) { keepAwake.select(mode, sessions: sessions); render() }
    func toggleKeepAwake() {
        if let pulse { Task { await pulse.toggle() }; return }
        if closedLid.isActive { Task { await closedLid.stop() }; return }
        if keepAwake.isActive { choosePower(.off) }
        else { choosePower(sessions.contains { $0.phase != .completed && $0.phase != .stopped } ? .untilTasksFinish : .thirtyMinutes) }
    }
    func hover(_ id: String?) {
        hoverTask?.cancel()
        if let id {
            closeTask?.cancel()
            guard !isPinned, selectedID != id || !isExpanded else { return }
            hoverTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(LorePreferences.shared.relaxedHover ? 350 : 180)) } catch { return }
                self?.open(id, detailed: false)
            }
        } else if !pointerInsidePanel { scheduleDismiss() }
    }
    func panelHover(_ inside: Bool) {
        pointerInsidePanel = inside
        if inside {
            closeTask?.cancel(); announcementTask?.cancel(); automaticPresentation = false
            if isDismissing, let selectedID { open(selectedID, detailed: showsDetails) }
        } else if !automaticPresentation { scheduleDismiss() }
    }
    func pin(_ id: String) {
        if isPinned && selectedID == id {
            isPinned = false
            if !pointerInsidePanel { scheduleDismiss() }
            return
        }
        isPinned = true; announcement = nil
        open(id, detailed: true)
    }
    func showDetails(_ id: String) {
        isPinned = false
        open(id, detailed: true)
    }
    func updateDisplayedRows() { experience.freezeRows(); render() }
    func fitPowerPanel(to height: CGFloat) {
        guard height.isFinite, height > 0, abs(powerContentHeight - height) > 0.5 else { return }
        powerContentHeight = ceil(height)
        if selectedID == Self.powerID && showsDetails { render() }
    }
    private func open(_ id: String, detailed: Bool, automatic: Bool = false) {
        hoverTask?.cancel(); closeTask?.cancel(); announcementTask?.cancel()
        guard id == Self.powerID || id == Self.agentsID else { return }
        isDismissing = false
        let wasClosed = selectedID == nil
        // Closing hides the content before clearing selection. Re-entering during
        // that interval must restart its reveal even when the same panel returns.
        let contentChanged = wasClosed || selectedID != id || showsDetails != detailed || !contentVisible
        if detailed && id == Self.agentsID && !experience.rowsAreFrozen { experience.freezeRows() }
        if !detailed || id == Self.powerID { experience.releaseRows() }
        selectedID = id; showsDetails = detailed; automaticPresentation = automatic
        if !automatic { announcement = nil }
        if contentChanged { contentVisible = false }
        isExpanded = !wasClosed
        render()
        if wasClosed {
            expandTask?.cancel()
            expandTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                self?.isExpanded = true
            }
        }
        if contentChanged {
            contentTask?.cancel()
            contentTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                self?.contentVisible = true
            }
        }
    }
    private func scheduleDismiss() {
        guard !isPinned, selectedID != nil, !isDismissing else { return }
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(LorePreferences.shared.relaxedHover ? 800 : 550)) } catch { return }
            guard let self, !isPinned, !pointerInsidePanel else { return }
            // Tracking events can arrive late after a window is resized/reused.
            // Check the actual pointer position before collapsing a live surface.
            if let panel = expandedPanel, panel.isVisible,
               panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) { return }
            dismiss()
        }
    }
    func dismiss() {
        hoverTask?.cancel(); closeTask?.cancel(); expandTask?.cancel(); contentTask?.cancel(); announcementTask?.cancel()
        isPinned = false; contentVisible = false; isExpanded = false; isDismissing = true
        closeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
            self?.selectedID = nil; self?.pointerInsidePanel = false; self?.announcement = nil; self?.isDismissing = false
            self?.automaticPresentation = false; self?.experience.releaseRows()
            self?.expandedPanel?.orderOut(nil); self?.render()
        }
    }
    private func showAnnouncement(_ notice: NotchAnnouncement) {
        guard isEnabled, announcementsEnabled, !isPinned, !pointerInsidePanel, selectedID == nil || automaticPresentation else { return }
        if announcement?.kind == .attention && notice.kind == .completed { return }
        announcement = notice
        open(Self.agentsID, detailed: false, automatic: true)
        announcementTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(NotchExperiencePolicy.announcementDuration)) } catch { return }
            guard self?.automaticPresentation == true else { return }
            self?.dismiss()
        }
    }
    private func suspend() { suspended = true; task?.cancel(); task = nil; keepAwake.stop(); hideAll() }
    private func resume() { suspended = false; sessions = []; experience.suppressNextAnnouncements(); start() }
    private func receive(_ snapshot: LiveMonitorSnapshot) {
        unreadableFiles = snapshot.unreadableFiles
        keepAwake.update(sessions: snapshot.sessions)
        sessions = snapshot.sessions
        let oldSummary = activitySummary
        let notice = experience.ingest(snapshot.sessions, at: .now)
        if let announcement, announcement.kind == .attention,
           !sessions.contains(where: { $0.id == announcement.session.id && $0.phase == .needsInput }) {
            self.announcement = nil
            if automaticPresentation { dismiss() }
        }
        if oldSummary != activitySummary || selectedID != nil { render() }
        if let notice { showAnnouncement(notice) }
    }
    private func geometry(for screen: NSScreen) -> NotchGeometry {
        NotchGeometry(screen: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
                      leftArea: screen.auxiliaryTopLeftArea ?? .zero, rightArea: screen.auxiliaryTopRightArea ?? .zero)
    }
    private func hideAll() {
        hoverTask?.cancel(); closeTask?.cancel(); expandTask?.cancel(); contentTask?.cancel(); announcementTask?.cancel()
        selectedID = nil; isExpanded = false; isPinned = false; pointerInsidePanel = false; isDismissing = false
        contentVisible = false; automaticPresentation = false; announcement = nil; experience.releaseRows()
        panels.forEach { $0.orderOut(nil) }; expandedPanel?.orderOut(nil)
    }
    private func render() {
        // Exercise transition timing in tests without creating desktop windows.
        guard rendersPanels else { return }
        guard isEnabled, !suspended,
              let screen = NSScreen.screens.first(where: { self.geometry(for: $0).cutout != nil }) ?? NSScreen.main else { hideAll(); return }
        let layout = geometry(for: screen)
        usesNotch = layout.cutout != nil
        while panels.count < 2 { panels.append(ActivityPanel()) }
        let leftWidth: CGFloat = 44, rightWidth: CGFloat = 44
        if selectedID != nil {
            if expandedPanel == nil { expandedPanel = ActivityPanel() }
            let camera = layout.cutout?.width ?? 12
            let collapsedWidth = leftWidth + camera + rightWidth
            let width = max(showsDetails ? 420 : 340, collapsedWidth + (showsDetails ? 24 : 12))
            let contentHeight: CGFloat = !showsDetails ? 88 : selectedID == Self.powerID ? powerContentHeight : min(420, max(144, 90 + CGFloat(experience.rows.count) * 56 + CGFloat(groups.count) * 28 + (pendingRowCount > 0 ? 32 : 0)))
            let height = layout.badgeHeight + contentHeight
            let centerX = layout.cutout?.midX ?? layout.visibleFrame.midX
            let originX = min(max(screen.frame.minX + 8, centerX - width / 2), screen.frame.maxX - width - 8)
            let top = usesNotch ? screen.frame.maxY : layout.visibleFrame.maxY - 6
            let view = ExpandedNotchView(controller: self, width: width, height: height, collapsedWidth: collapsedWidth, cameraWidth: camera, topHeight: layout.badgeHeight)
            show(expandedPanel!, frame: CGRect(x: originX, y: top - height, width: width, height: height), view: view,
                 regions: [NotchHoverRegion(id: Self.powerID, rect: CGRect(x: (width - camera) / 2 - 44, y: 0, width: 44, height: layout.badgeHeight)),
                           NotchHoverRegion(id: Self.agentsID, rect: CGRect(x: (width + camera) / 2, y: 0, width: 44, height: layout.badgeHeight))], tracksPanel: true)
            panels.forEach { $0.orderOut(nil) }
            return
        }
        expandedPanel?.orderOut(nil)
        if usesNotch {
            let overlap = layout.seamOverlap(backingScale: screen.backingScaleFactor)
            if let frame = layout.joinedWing(side: .left, width: leftWidth, backingScale: screen.backingScaleFactor) {
                show(panels[0], frame: frame, view: PulseBadgeView(controller: self).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.trailing, overlap).background(NotchSurface.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 13)).preferredColorScheme(.dark),
                     regions: [NotchHoverRegion(id: Self.powerID, rect: CGRect(x: 0, y: 0, width: 44, height: layout.badgeHeight))])
            }
            if let frame = layout.joinedWing(side: .right, width: rightWidth, backingScale: screen.backingScaleFactor) {
                show(panels[1], frame: frame, view: AIActivityBadgeView(controller: self).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, overlap).background(NotchSurface.black, in: UnevenRoundedRectangle(bottomTrailingRadius: 13)).preferredColorScheme(.dark),
                     regions: [NotchHoverRegion(id: Self.agentsID, rect: CGRect(x: overlap, y: 0, width: 44, height: layout.badgeHeight))])
            }
        } else {
            show(panels[0], frame: layout.fallback(width: leftWidth + 12 + rightWidth),
                 view: HStack(spacing: 12) { PulseBadgeView(controller: self); AIActivityBadgeView(controller: self) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(NotchSurface.black, in: RoundedRectangle(cornerRadius: 15)).preferredColorScheme(.dark),
                 regions: [NotchHoverRegion(id: Self.powerID, rect: CGRect(x: 0, y: 0, width: 44, height: layout.badgeHeight)),
                           NotchHoverRegion(id: Self.agentsID, rect: CGRect(x: 56, y: 0, width: 44, height: layout.badgeHeight))])
            panels[1].orderOut(nil)
        }
    }
    private func show<V: View>(_ panel: ActivityPanel, frame: CGRect, view: V, regions: [NotchHoverRegion], tracksPanel: Bool = false) {
        let host: NotchHostingView<V>
        let updatesExistingHost: Bool
        if let existing = panel.contentView as? NotchHostingView<V> {
            host = existing
            updatesExistingHost = true
        }
        else {
            host = NotchHostingView(rootView: view); host.sizingOptions = []; host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor; host.layer?.borderWidth = 0
            panel.contentView = host
            updatesExistingHost = false
        }
        host.onRegionHover = { [weak self] id in self?.hover(id) }
        host.onPanelHover = tracksPanel ? { [weak self] inside in self?.panelHover(inside) } : nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0; context.allowsImplicitAnimation = false
            panel.setFrame(frame, display: false)
            if updatesExistingHost {
                host.rootView = view
                host.needsLayout = true
            }
        }
        host.configure(regions: regions, tracksPanel: tracksPanel)
        panel.orderFrontRegardless()
        host.synchronizeHover(reportPanelState: true)
    }
}
