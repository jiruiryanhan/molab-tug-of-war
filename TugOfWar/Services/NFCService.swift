import Foundation
import Observation
#if canImport(CoreNFC)
import CoreNFC
#endif

/// Join by tapping a tag: the host writes the room's join link to any NDEF tag, players
/// scan it. Needs a real iPhone (XS or newer) and the NFC capability on the app's team.
@MainActor
@Observable
final class NFCService {
    var statusMessage: String?

    #if canImport(CoreNFC)
    var isBusy: Bool { reader != nil || writer != nil }
    #else
    var isBusy: Bool { false }
    #endif

    static var isAvailable: Bool {
        #if canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    #if canImport(CoreNFC)
    private var reader: ReadDelegate?
    private var writer: WriteDelegate?
    #endif

    /// Scan a tag and hand back the join URL it carries.
    func scanForJoinLink(_ completion: @escaping @MainActor (URL?) -> Void) {
        #if canImport(CoreNFC)
        guard Self.isAvailable else { statusMessage = "NFC is not available on this device."; completion(nil); return }
        guard reader == nil else { return }   // a scan is already on screen
        let delegate = ReadDelegate { [weak self] url, message in
            self?.statusMessage = message
            completion(url)
            self?.reader = nil
        }
        reader = delegate
        let session = NFCNDEFReaderSession(delegate: delegate, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = "Hold your iPhone near the Tug of War tag."
        session.begin()
        #else
        statusMessage = "NFC is not available on this device."
        completion(nil)
        #endif
    }

    /// Write the join link onto a blank/rewritable NDEF tag.
    func write(url: URL, _ completion: @escaping @MainActor (Bool) -> Void) {
        #if canImport(CoreNFC)
        guard Self.isAvailable else { statusMessage = "NFC is not available on this device."; completion(false); return }
        guard writer == nil else { return }   // a write is already on screen
        let delegate = WriteDelegate(url: url) { [weak self] ok, message in
            self?.statusMessage = message
            completion(ok)
            self?.writer = nil
        }
        writer = delegate
        let session = NFCNDEFReaderSession(delegate: delegate, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = "Hold your iPhone near a blank NFC tag to write the room link."
        session.begin()
        #else
        statusMessage = "NFC is not available on this device."
        completion(false)
        #endif
    }
}

#if canImport(CoreNFC)
/// Reading uses the simple NDEF path: iOS reads the tag and gives us the messages.
private final class ReadDelegate: NSObject, NFCNDEFReaderSessionDelegate {
    let done: @MainActor (URL?, String?) -> Void
    private var finished = false

    init(done: @escaping @MainActor (URL?, String?) -> Void) { self.done = done }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                if let url = record.wellKnownTypeURIPayload(), JoinLink.code(from: url) != nil {
                    finish(url, "Found room link.")
                    session.alertMessage = "Joining…"
                    return
                }
            }
        }
        finish(nil, "That tag does not hold a Tug of War link.")
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        let cancelled = nfcError?.code == .readerSessionInvalidationErrorUserCanceled
            || nfcError?.code == .readerSessionInvalidationErrorFirstNDEFTagRead
        finish(nil, cancelled ? nil : error.localizedDescription)
    }

    private func finish(_ url: URL?, _ message: String?) {
        guard !finished else { return }
        finished = true
        let done = self.done
        Task { @MainActor in done(url, message) }
    }
}

/// Writing needs the tag object itself, so this delegate implements `didDetect tags:`.
private final class WriteDelegate: NSObject, NFCNDEFReaderSessionDelegate {
    let url: URL
    let done: @MainActor (Bool, String?) -> Void
    private var finished = false

    init(url: URL, done: @escaping @MainActor (Bool, String?) -> Void) {
        self.url = url
        self.done = done
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        if tags.count > 1 {
            session.alertMessage = "More than one tag found. Hold only one near the phone."
            session.restartPolling()
            return
        }
        session.connect(to: tag) { error in
            if let error { session.invalidate(errorMessage: error.localizedDescription); return }
            tag.queryNDEFStatus { status, _, error in
                if let error { session.invalidate(errorMessage: error.localizedDescription); return }
                guard status == .readWrite else {
                    session.invalidate(errorMessage: status == .readOnly ? "This tag is read-only." : "This tag does not support NDEF.")
                    return
                }
                guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: self.url) else {
                    session.invalidate(errorMessage: "Could not build the tag payload.")
                    return
                }
                tag.writeNDEF(NFCNDEFMessage(records: [payload])) { error in
                    if let error {
                        session.invalidate(errorMessage: error.localizedDescription)
                    } else {
                        session.alertMessage = "Tag written. Friends can tap it to join."
                        self.finish(true, "Tag written.")
                        session.invalidate()
                    }
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let cancelled = (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled
        finish(false, cancelled ? nil : error.localizedDescription)
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    private func finish(_ ok: Bool, _ message: String?) {
        guard !finished else { return }
        finished = true
        let done = self.done
        Task { @MainActor in done(ok, message) }
    }
}
#endif
