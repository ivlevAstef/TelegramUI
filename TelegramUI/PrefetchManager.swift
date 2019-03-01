import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore

private final class PrefetchMediaContext {
    let media: HolesViewMedia
    let fetchDisposable = MetaDisposable()
    
    init(media: HolesViewMedia) {
        self.media = media
    }
}

private final class PrefetchManagerImpl {
    private let queue: Queue
    private let account: Account
    private let fetchManager: FetchManager
    
    private var listDisposable: Disposable?
    
    private var contexts: [MediaId: PrefetchMediaContext] = [:]
    
    init(queue: Queue, sharedContext: SharedAccountContext, account: Account, fetchManager: FetchManager) {
        self.queue = queue
        self.account = account
        self.fetchManager = fetchManager
        
        let networkType = account.networkType
        |> map { networkType -> MediaAutoDownloadNetworkType in
            switch networkType {
                case .none, .cellular:
                    return.cellular
                case .wifi:
                    return .wifi
            }
        }
        |> distinctUntilChanged
        
        self.listDisposable = (combineLatest(account.viewTracker.orderedPreloadMedia, sharedContext.automaticMediaDownloadSettings, networkType)
        |> deliverOn(self.queue)).start(next: { [weak self] orderedPreloadMedia, automaticDownloadSettings, networkType in
            self?.updateOrderedPreloadMedia(orderedPreloadMedia, automaticDownloadSettings: automaticDownloadSettings, networkType: networkType)
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.listDisposable?.dispose()
    }
    
    private func updateOrderedPreloadMedia(_ orderedPreloadMedia: [HolesViewMedia], automaticDownloadSettings: MediaAutoDownloadSettings, networkType: MediaAutoDownloadNetworkType) {
        var validIds = Set<MediaId>()
        for mediaItem in orderedPreloadMedia {
            guard let id = mediaItem.media.id else {
                continue
            }
            
            var automaticDownload: InteractiveMediaNodeAutodownloadMode = .none
            let peerType: MediaAutoDownloadPeerType
            if mediaItem.authorIsContact {
                peerType = .contact
            } else if let channel = mediaItem.peer as? TelegramChannel {
                if case .group = channel.info {
                    peerType = .group
                } else {
                    peerType = .channel
                }
            } else if mediaItem.peer is TelegramGroup {
                peerType = .group
            } else {
                peerType = .otherPrivate
            }
            var mediaResource: MediaResource?
            
            if let telegramImage = mediaItem.media as? TelegramMediaImage {
                mediaResource = largestRepresentationForPhoto(telegramImage)?.resource
                if shouldDownloadMediaAutomatically(settings: automaticDownloadSettings, peerType: peerType, networkType: networkType, authorPeerId: nil, contactsPeerIds: [], media: telegramImage) {
                    automaticDownload = .full
                }
            } else if let telegramFile = mediaItem.media as? TelegramMediaFile {
                mediaResource = telegramFile.resource
                if shouldDownloadMediaAutomatically(settings: automaticDownloadSettings, peerType: peerType, networkType: networkType, authorPeerId: nil, contactsPeerIds: [], media: telegramFile) {
                    automaticDownload = .full
                } else if shouldPredownloadMedia(settings: automaticDownloadSettings, peerType: peerType, networkType: networkType, media: telegramFile) {
                    automaticDownload = .prefetch
                }
            }
            
            if case .none = automaticDownload {
                continue
            }
            guard let resource = mediaResource else {
                continue
            }
            
            validIds.insert(id)
            let context: PrefetchMediaContext
            if let current = self.contexts[id] {
                context = current
            } else {
                context = PrefetchMediaContext(media: mediaItem)
                self.contexts[id] = context
                
                let media = mediaItem.media
                
                if case .full = automaticDownload {
                    if let image = media as? TelegramMediaImage {
                        context.fetchDisposable.set(messageMediaImageInteractiveFetched(fetchManager: self.fetchManager, messageId: mediaItem.index.id, messageReference: MessageReference(peer: mediaItem.peer, id: mediaItem.index.id, timestamp: mediaItem.index.timestamp, incoming: true, secret: false), image: image, resource: resource, userInitiated: false, priority: .backgroundPrefetch(mediaItem.index), storeToDownloadsPeerType: nil).start())
                    } else if let _ = media as? TelegramMediaWebFile {
                        //strongSelf.fetchDisposable.set(chatMessageWebFileInteractiveFetched(account: context.account, image: image).start())
                    } else if let file = media as? TelegramMediaFile {
                        let fetchSignal = messageMediaFileInteractiveFetched(fetchManager: self.fetchManager, messageId: mediaItem.index.id, messageReference: MessageReference(peer: mediaItem.peer, id: mediaItem.index.id, timestamp: mediaItem.index.timestamp, incoming: true, secret: false), file: file, userInitiated: false, priority: .backgroundPrefetch(mediaItem.index))
                        context.fetchDisposable.set(fetchSignal.start())
                    }
                } else if case .prefetch = automaticDownload, mediaItem.peer.id.namespace != Namespaces.Peer.SecretChat {
                    if let file = media as? TelegramMediaFile, let fileSize = file.size {
                        let fetchHeadRange: Range<Int> = 0 ..< 2 * 1024 * 1024
                        let fetchTailRange: Range<Int> = fileSize - 256 * 1024 ..< Int(Int32.max)
                        
                        var ranges = IndexSet()
                        ranges.insert(integersIn: fetchHeadRange)
                        ranges.insert(integersIn: fetchTailRange)
                        
                        let fetchSignal = messageMediaFileInteractiveFetched(fetchManager: self.fetchManager, messageId: mediaItem.index.id, messageReference: MessageReference(peer: mediaItem.peer, id: mediaItem.index.id, timestamp: mediaItem.index.timestamp, incoming: true, secret: false), file: file, ranges: ranges, userInitiated: false, priority: .backgroundPrefetch(mediaItem.index))
                        context.fetchDisposable.set(fetchSignal.start())
                    }
                }
            }
        }
        var removeIds: [MediaId] = []
        for key in self.contexts.keys {
            if !validIds.contains(key) {
                removeIds.append(key)
            }
        }
        for id in removeIds {
            if let context = self.contexts.removeValue(forKey: id) {
                context.fetchDisposable.dispose()
            }
        }
    }
}

final class PrefetchManager {
    private let queue: Queue
    
    private let impl: QueueLocalObject<PrefetchManagerImpl>
    
    init(sharedContext: SharedAccountContext, account: Account, fetchManager: FetchManager) {
        let queue = Queue.mainQueue()
        self.queue = queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return PrefetchManagerImpl(queue: queue, sharedContext: sharedContext, account: account, fetchManager: fetchManager)
        })
    }
}
