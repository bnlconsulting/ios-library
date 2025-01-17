/* Copyright Airship and Contributors */

// NOTE: For internal use only. :nodoc:
@objc(UARemoteDataManager)
public class RemoteDataManager : NSObject, Component, RemoteDataProvider {
    
    static let refreshTaskID = "RemoteDataManager.refresh"
    static let defaultRefreshInterval: TimeInterval = 10
    static let refreshRemoteDataPushPayloadKey = "com.urbanairship.remote-data.update";

    // Datastore keys
    private static let refreshIntervalKey = "remotedata.REFRESH_INTERVAL"
    private static let lastRefreshMetadataKey = "remotedata.LAST_REFRESH_METADATA"
    private static let lastRefreshTimeKey = "remotedata.LAST_REFRESH_TIME"
    private static let lastRefreshAppVersionKey = "remotedata.LAST_REFRESH_APP_VERSION"
    private static let lastRemoteDataModifiedTime = "UALastRemoteDataModifiedTime"

    private let dataStore: PreferenceDataStore
    private let apiClient: RemoteDataAPIClientProtocol
    private let remoteDataStore: RemoteDataStore
    private let dispatcher: UADispatcher
    private let date: DateUtils
    private let notificationCenter: NotificationCenter
    private let appStateTracker: AppStateTracker
    private let localeManager: LocaleManagerProtocol
    private let taskManager: TaskManagerProtocol
    private let privacyManager: PrivacyManager
    
    private var subscriptions: [UUID : RemoteDataSubscription] = [:]
    private var updatedSinceLastForeground = false
    
    public var remoteDataRefreshInterval: TimeInterval {
        get {
            let fromStore = self.dataStore.object(forKey: RemoteDataManager.refreshIntervalKey ) as? TimeInterval
            return  fromStore ?? RemoteDataManager.defaultRefreshInterval
        }
        set {
            self.dataStore.setDouble(newValue, forKey: RemoteDataManager.refreshIntervalKey)
        }
    }
    
    private var lastMetadata: [AnyHashable : Any]? {
        get {
            return self.dataStore.object(forKey: RemoteDataManager.lastRefreshMetadataKey) as? [AnyHashable : Any]
        }
        set {
            self.dataStore.setObject(newValue, forKey: RemoteDataManager.lastRefreshMetadataKey)
        }
    }
    
    private var lastModified : String? {
        get {
            return self.dataStore.string(forKey: RemoteDataManager.lastRemoteDataModifiedTime)
        }
        set {
            self.dataStore.setObject(newValue, forKey: RemoteDataManager.lastRemoteDataModifiedTime)
        }
    }
    
    private var lastRefreshTime : Date {
        get {
            return self.dataStore.object(forKey: RemoteDataManager.lastRefreshTimeKey) as? Date ?? Date.distantPast
        }
        set {
            self.dataStore.setValue(newValue, forKey: RemoteDataManager.lastRefreshTimeKey)
        }
    }
    
    private var lastAppVersion : String? {
        get {
            return self.dataStore.string(forKey: RemoteDataManager.lastRefreshAppVersionKey)
        }
        set {
            self.dataStore.setValue(newValue, forKey: RemoteDataManager.lastRefreshAppVersionKey)
        }
    }
    
    private let disableHelper: ComponentDisableHelper
        
    // NOTE: For internal use only. :nodoc:
    public var isComponentEnabled: Bool {
        get {
            return disableHelper.enabled
        }
        set {
            disableHelper.enabled = newValue
        }
    }

    
    @objc
    public convenience init(config: RuntimeConfig,
                            dataStore: PreferenceDataStore,
                            localeManager: LocaleManagerProtocol,
                            privacyManager: PrivacyManager) {

        self.init(dataStore: dataStore,
                  localeManager: localeManager,
                  privacyManager: privacyManager,
                  apiClient: RemoteDataAPIClient(config: config),
                  remoteDataStore: RemoteDataStore(storeName: "RemoteData-\(config.appKey).sqlite"),
                  taskManager: TaskManager.shared,
                  dispatcher: UADispatcher.main,
                  date: DateUtils(),
                  notificationCenter: NotificationCenter.default,
                  appStateTracker: AppStateTracker.shared)
                     
    }
    
    @objc
    public init(dataStore: PreferenceDataStore,
                localeManager: LocaleManagerProtocol,
                privacyManager: PrivacyManager,
                apiClient: RemoteDataAPIClientProtocol,
                remoteDataStore: RemoteDataStore,
                taskManager: TaskManagerProtocol,
                dispatcher: UADispatcher,
                date: DateUtils,
                notificationCenter: NotificationCenter,
                appStateTracker: AppStateTracker) {
        
        self.dataStore = dataStore
        self.localeManager = localeManager
        self.privacyManager = privacyManager
        self.apiClient = apiClient
        self.remoteDataStore = remoteDataStore
        self.taskManager = taskManager
        self.dispatcher = dispatcher
        self.date = date
        self.notificationCenter = notificationCenter
        self.appStateTracker = appStateTracker
        
        self.disableHelper = ComponentDisableHelper(dataStore: dataStore,
                                                    className: "UARemoteDataManager")

        super.init()
        
        self.notificationCenter.addObserver(self,
                                            selector: #selector(checkRefresh),
                                            name: LocaleManager.localeUpdatedEvent,
                                            object: nil)
        
        self.notificationCenter.addObserver(self,
                                            selector: #selector(applicationDidForeground),
                                            name: AppStateTracker.didTransitionToForeground,
                                            object: nil)
        
        self.notificationCenter.addObserver(self,
                                            selector: #selector(enqueueRefreshTask),
                                            name: RuntimeConfig.configUpdatedEvent,
                                            object: nil)
        
        self.notificationCenter.addObserver(self,
                                            selector: #selector(checkRefresh),
                                            name: PrivacyManager.changeEvent,
                                            object: nil)
        
        self.taskManager.register(taskID: RemoteDataManager.refreshTaskID, dispatcher: UADispatcher.serial()) { [weak self] task in
            
            guard let self = self,
                  self.privacyManager.isAnyFeatureEnabled() else {
                task.taskCompleted()
                return
            }
            
            self.handleRefreshTask(task)
        }

        self.checkRefresh()
    }
    
    @objc
    private func checkRefresh() {
        if (self.shouldRefresh()) {
            self.enqueueRefreshTask()
        }
    }
    
    @objc
    private func applicationDidForeground() {
        self.updatedSinceLastForeground = false
        self.checkRefresh()
    }
    
    @objc
    private func enqueueRefreshTask() {
        if (self.privacyManager.isAnyFeatureEnabled()) {
            self.taskManager.enqueueRequest(taskID: RemoteDataManager.refreshTaskID, options: TaskRequestOptions.defaultOptions)
        }
    }
    
    private func handleRefreshTask(_ task: Task) {
        let lastModified = self.isLastMetadataCurrent() ? self.lastModified : nil
        let locale = self.localeManager.currentLocale
        
        let semaphore = Semaphore()
        
        let request = self.apiClient.fetchRemoteData(locale: locale, lastModified: lastModified) { response, error in
            guard let response = response else {
                if let error = error {
                    AirshipLogger.error("Failed to refresh remote-data with error \(error)")
                } else {
                    AirshipLogger.error("Failed to refresh remote-data")
                }
                
                task.taskFailed()
                semaphore.signal()
                return
            }
            
            AirshipLogger.debug("Remote data refresh finished with response: \(response)")
            AirshipLogger.trace("Remote data refresh finished with payloads: \(response.payloads ?? [])")

            if (response.status == 304) {
                self.updatedSinceLastForeground = true
                self.lastRefreshTime = self.date.now
                self.lastAppVersion = Utils.bundleShortVersionString()
                task.taskCompleted()
                semaphore.signal()
            } else if (response.isSuccess) {
                let payloads = response.payloads ?? []

                self.remoteDataStore.overwriteCachedRemoteData(payloads) { success in
                    if (success) {
                        
                        self.lastMetadata = response.metadata
                        self.lastModified = response.lastModified
                        self.lastRefreshTime = self.date.now
                        self.lastAppVersion = Utils.bundleShortVersionString()
                        self.notifySubscribers(payloads) {
                            self.updatedSinceLastForeground = true
                            task.taskCompleted()
                            semaphore.signal()
                        }
                    } else {
                        AirshipLogger.error("Failed to save remote-data.")
                        task.taskFailed()
                        semaphore.signal()
                    }
                }
            } else {
                AirshipLogger.debug("Failed to refresh remote-data")
                if (response.isServerError) {
                    task.taskFailed()
                } else {
                    task.taskCompleted()
                }
                semaphore.signal()
            }
        }
        
        task.expirationHandler = {
            request.dispose()
        }
        
        semaphore.wait()
    }
    
    private func notifySubscribers(_ payloads: [RemoteDataPayload], completionHandler: @escaping () -> Void) {
        let dispatchGroup = DispatchGroup()
        let subscriptions = self.subscriptions.values
        
        subscriptions.forEach { subscription in
            let subscriptionPayloads = payloads.filter {
                subscription.payloadTypes.contains($0.type)
            }
            
            dispatchGroup.enter()
            subscription.notify(payloads: subscriptionPayloads, dispatcher: self.dispatcher) {
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: DispatchQueue.global(qos: .default)) {
            completionHandler()
        }
    }

    private func createMetadata(locale: Locale) -> [AnyHashable : Any] {
        return self.apiClient.metadata(locale: locale)
    }

    public func isMetadataCurrent(_ metadata: [AnyHashable : Any]) -> Bool {
        let last = (self.lastMetadata ?? [:]) as NSDictionary
        let metadata = metadata as NSDictionary
        return metadata.isEqual(last)
    }

    private func isLastAppVersionCurrent() -> Bool {
        let lastAppRefreshVersion = self.dataStore.string(forKey: RemoteDataManager.lastRefreshAppVersionKey)
        let currentAppVersion = Utils.bundleShortVersionString()
        return lastAppRefreshVersion == currentAppVersion
    }
    
    private func isLastMetadataCurrent() -> Bool {
        let current = self.createMetadata(locale: self.localeManager.currentLocale)
        return isMetadataCurrent(current)
    }
    
    private func shouldRefresh() -> Bool {
        guard self.privacyManager.isAnyFeatureEnabled(),
              self.appStateTracker.state == .active else {
            return false
        }
        
        guard self.isLastAppVersionCurrent(),
              self.isLastMetadataCurrent()  else {
            return true
        }
        
        if (!self.updatedSinceLastForeground) {
            let timeSinceLastRefresh = self.date.now.timeIntervalSince(self.lastRefreshTime)
            if (timeSinceLastRefresh >= self.remoteDataRefreshInterval) {
                return true
            }
        }
        
        return false
    }
    
    @discardableResult
    public func subscribe(types: [String], block:@escaping ([RemoteDataPayload]) -> Void) -> Disposable {
        let subscriptionID = UUID()
        let subscription = RemoteDataSubscription(payloadTypes: types, publishBlock: block)
        self.subscriptions[subscriptionID] = subscription
        
        let disposable = Disposable() {
            subscription.cancel()
            self.subscriptions[subscriptionID] = nil
        }
        
        self.notifySubscriber(subscription: subscription)
        return disposable
    }
    
    
    private func notifySubscriber(subscription: RemoteDataSubscription) {
        let predicate = NSPredicate(format: "(type IN %@)", subscription.payloadTypes)
        self.remoteDataStore.fetchRemoteDataFromCache(predicate: predicate) { [weak self] payloads in
            guard let self = self else { return }
            subscription.notify(payloads: payloads, dispatcher: self.dispatcher){}
        }
    }
}

extension RemoteDataManager : PushableComponent {
    public func receivedRemoteNotification(_ notification: [AnyHashable : Any], completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if (notification[RemoteDataManager.refreshRemoteDataPushPayloadKey] == nil) {
            completionHandler(.noData)
        } else {
            self.enqueueRefreshTask()
            completionHandler(.newData);
        }
    }
}

internal class RemoteDataSubscription {
    let payloadTypes: [String]
    private(set) var publishBlock: (([RemoteDataPayload]) -> Void)?
    private var previousPayloadTimeStamps: [String : Date] = [:]
    private var previousMetadata: [String : [AnyHashable : Any]] = [:]

    init(payloadTypes: [String], publishBlock: @escaping ([RemoteDataPayload]) -> Void) {
        self.payloadTypes = payloadTypes
        self.publishBlock = publishBlock
    }
    
    func notify(payloads: [RemoteDataPayload], dispatcher: UADispatcher, completionHandler: @escaping () -> Void) {
        var payloads = payloads
        payloads.sort { first, second in
            let firstIndex = payloadTypes.firstIndex(of: first.type) ?? 0
            let secondIndex = payloadTypes.firstIndex(of: second.type) ?? 0
            return firstIndex < secondIndex
        }
        
        dispatcher.dispatchAsync { [weak self] in
            let updated = payloads.contains(where: {
                let date = self?.previousPayloadTimeStamps[$0.type]
                let metadata = self?.previousMetadata[$0.type]
                return date != $0.timestamp || (metadata as NSDictionary?) != ($0.metadata as NSDictionary?)
            })
            
            if (payloads.isEmpty || updated) {
                self?.publishBlock?(payloads)
                payloads.forEach {
                    self?.previousPayloadTimeStamps[$0.type] = $0.timestamp
                    self?.previousMetadata[$0.type] = $0.metadata
                }
            }
            completionHandler()
        }
    }
    func cancel() {
        self.publishBlock = nil
    }
}
