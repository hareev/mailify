import Foundation
@preconcurrency import Dispatch
import Darwin

/// A minimal, single-use local HTTP listener on 127.0.0.1 used only to catch
/// Google's OAuth redirect. Google disallows custom URI scheme redirects for
/// "Desktop app" OAuth clients (an app claiming an arbitrary scheme could
/// impersonate another app), so the supported native-app flow is: open the
/// system browser, have Google redirect to a loopback address, and have the
/// app itself listening there for the one incoming request. See
/// https://developers.google.com/identity/protocols/oauth2/native-app.
///
/// Uses raw POSIX sockets, not Network.framework's NWListener: NWListener
/// failed to bind at all in this app's runtime ("NWError 22" / EINVAL), and
/// the same failure reproduced in isolation for every parameter combination
/// tried — including the bare-minimum `NWListener(using: .tcp)` with no
/// extra configuration at all — which points at Network.framework itself in
/// this environment, not anything about how it was being configured. Raw
/// sockets are a completely different code path that doesn't go through
/// Network.framework's validation, so this sidesteps the issue entirely.
final class OAuthLoopbackServer: @unchecked Sendable {
    private let socketFD: Int32
    let port: UInt16

    // Guards `stopped`, the only mutable state touched from more than one
    // queue (the accept() background queue and the timeout's queue).
    private let lock = NSLock()
    private var stopped = false

    enum LoopbackError: LocalizedError {
        case bindFailed(String)
        case connectionClosed
        case authorizationFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .bindFailed(let reason): return "Couldn't start the local sign-in listener: \(reason)"
            case .connectionClosed: return "The sign-in browser tab closed before completing."
            case .authorizationFailed(let reason): return "Google sign-in failed: \(reason)"
            case .timedOut: return "Sign-in timed out. Try again."
            }
        }
    }

    private init(socketFD: Int32, port: UInt16) {
        self.socketFD = socketFD
        self.port = port
    }

    /// Binds a TCP socket to 127.0.0.1 on an OS-assigned ephemeral port.
    static func start() throws -> OAuthLoopbackServer {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LoopbackError.bindFailed("socket() failed: \(currentErrnoMessage())")
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ask the OS for an ephemeral port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { rawAddr -> Int32 in
            rawAddr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let message = currentErrnoMessage()
            close(fd)
            throw LoopbackError.bindFailed("bind() failed: \(message)")
        }

        guard listen(fd, 1) == 0 else {
            let message = currentErrnoMessage()
            close(fd)
            throw LoopbackError.bindFailed("listen() failed: \(message)")
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) { rawAddr -> Int32 in
            rawAddr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(fd, sockaddrPtr, &boundLen)
            }
        }
        guard nameResult == 0 else {
            let message = currentErrnoMessage()
            close(fd)
            throw LoopbackError.bindFailed("getsockname() failed: \(message)")
        }

        return OAuthLoopbackServer(socketFD: fd, port: UInt16(bigEndian: boundAddr.sin_port))
    }

    /// Waits for the single incoming redirect request, extracts the
    /// authorization code (or error) from its query string, replies with a
    /// short confirmation page, and shuts the listener down. Times out after
    /// 5 minutes so an abandoned sign-in doesn't leak the listener forever.
    ///
    /// `accept`/`recv` are blocking POSIX calls, so this work runs on a
    /// background queue; `lock` guards the single-fire resume between that
    /// queue and the timeout's queue.
    func waitForAuthorizationCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let resume: (Result<String, Error>) -> Void = { [lock] result in
                lock.lock()
                let alreadyResumed = didResume
                didResume = true
                lock.unlock()
                guard !alreadyResumed else { return }
                continuation.resume(with: result)
            }

            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.stopDueToTimeout()
                resume(.failure(LoopbackError.timedOut))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 300, execute: timeoutWorkItem)

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let clientFD = accept(self.socketFD, nil, nil)
                timeoutWorkItem.cancel()

                self.lock.lock()
                let wasStoppedByTimeout = self.stopped
                self.lock.unlock()

                guard clientFD >= 0 else {
                    // If we were stopped by the timeout, it already resumed
                    // with .timedOut — closing the fd is what unblocked accept().
                    if !wasStoppedByTimeout {
                        resume(.failure(LoopbackError.connectionClosed))
                    }
                    return
                }
                defer { close(clientFD) }

                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = recv(clientFD, &buffer, buffer.count, 0)
                guard bytesRead > 0 else {
                    resume(.failure(LoopbackError.connectionClosed))
                    return
                }
                let requestText = String(decoding: buffer[0..<bytesRead], as: UTF8.self)

                let parsed = Self.parseAuthorizationResult(fromRequestText: requestText)
                Self.sendResponse(for: parsed, on: clientFD)

                self.stop()
                resume(parsed.mapError { $0 as Error })
            }
        }
    }

    /// Pure parsing of the redirect request's query string, pulled out so
    /// it's unit testable without a live socket at all — see Eval/main.swift.
    static func parseAuthorizationResult(fromRequestText requestText: String) -> Result<String, LoopbackError> {
        let requestLine = requestText.components(separatedBy: "\r\n").first ?? ""
        let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let query = URLComponents(string: "http://127.0.0.1\(path)")?.queryItems ?? []

        if let code = query.first(where: { $0.name == "code" })?.value {
            return .success(code)
        } else {
            let reason = query.first(where: { $0.name == "error" })?.value ?? "unknown_error"
            return .failure(.authorizationFailed(reason))
        }
    }

    private static func sendResponse(for parsed: Result<String, LoopbackError>, on clientFD: Int32) {
        let message: String
        switch parsed {
        case .success:
            message = "Mailify is connected. You can close this tab."
        case .failure(.authorizationFailed(let reason)):
            message = "Sign-in failed (\(reason)). You can close this tab and try again in Mailify."
        case .failure:
            message = "Sign-in failed. You can close this tab and try again in Mailify."
        }
        let html = "<html><body style=\"font-family:-apple-system;text-align:center;padding-top:4em;\">\(message)</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        response.withCString { cString in
            _ = send(clientFD, cString, strlen(cString), 0)
        }
    }

    private func stopDueToTimeout() {
        lock.lock()
        stopped = true
        lock.unlock()
        close(socketFD)
    }

    func stop() {
        lock.lock()
        let alreadyStopped = stopped
        stopped = true
        lock.unlock()
        guard !alreadyStopped else { return }
        close(socketFD)
    }

    private static func currentErrnoMessage() -> String {
        String(cString: strerror(errno))
    }
}
