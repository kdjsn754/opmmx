import Foundation

/// Serializes NMSSH access. NMSSH is not thread-safe, so every session
/// operation runs on the same private queue.
final class SSHService {
    private let queue = DispatchQueue(label: "com.catmint.openwrtmonitor.ssh")
    private var session: NMSSHSession?

    func connect(host: String, port: Int, user: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.session?.disconnect()
                self.session = nil

                let session = NMSSHSession(host: host, port: port, andUsername: user)
                session.timeout = NSNumber(value: 10)
                guard session.connect() else {
                    continuation.resume(throwing: AppError.message(
                        session.lastError?.localizedDescription ?? "SSH 连接失败"
                    ))
                    return
                }
                guard session.authenticate(byPassword: password) else {
                    session.disconnect()
                    continuation.resume(throwing: AppError.message(
                        session.lastError?.localizedDescription ?? "SSH 密码认证失败"
                    ))
                    return
                }
                self.session = session
                continuation.resume()
            }
        }
    }

    func execute(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                guard let session = self.session, session.isAuthorized else {
                    continuation.resume(throwing: AppError.notConnected)
                    return
                }
                var error: NSError?
                let output = session.channel.execute(command, error: &error)
                if let error {
                    continuation.resume(throwing: AppError.message(error.localizedDescription))
                } else {
                    continuation.resume(returning: output)
                }
            }
        }
    }

    func disconnect() {
        queue.async {
            self.session?.disconnect()
            self.session = nil
        }
    }
}
