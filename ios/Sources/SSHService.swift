import Foundation
import Darwin

/// Small libssh2 wrapper. NMSSH's CFSocket connection path does not work
/// reliably on current iOS releases, so this uses a normal BSD socket and
/// libssh2 directly. Every operation runs on the same private queue.
final class SSHService {
    private let queue = DispatchQueue(label: "com.catmint.openwrtmonitor.ssh")
    private var session: OpaquePointer?
    private var socketFD: Int32 = -1

    func connect(host: String, port: Int, user: String, password: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.closeLocked()
                libssh2_init(0)

                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(throwing: AppError.message("无法创建 TCP socket"))
                    return
                }

                var timeout = timeval(tv_sec: 10, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                           socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout,
                           socklen_t(MemoryLayout<timeval>.size))

                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(UInt16(port).bigEndian)
                guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
                    close(fd)
                    continuation.resume(throwing: AppError.message("路由器地址不是有效的 IPv4"))
                    return
                }

                let connectResult = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard connectResult == 0 else {
                    let code = errno
                    close(fd)
                    continuation.resume(throwing: AppError.message(
                        "TCP 连接失败：\(String(cString: strerror(code)))（errno \(code)）"
                    ))
                    return
                }

                guard let ssh = libssh2_session_init() else {
                    close(fd)
                    continuation.resume(throwing: AppError.message("libssh2 初始化失败"))
                    return
                }
                libssh2_session_set_blocking(ssh, 1)

                guard libssh2_session_handshake(ssh, fd) == 0 else {
                    let message = Self.lastError(ssh)
                    libssh2_session_free(ssh)
                    close(fd)
                    continuation.resume(throwing: AppError.message("SSH 握手失败：\(message)"))
                    return
                }

                let authResult = user.withCString { userPointer in
                    password.withCString { passwordPointer in
                        libssh2_userauth_password(ssh, userPointer, passwordPointer)
                    }
                }
                guard authResult == 0 else {
                    let message = Self.lastError(ssh)
                    libssh2_session_disconnect(ssh, "auth failed")
                    libssh2_session_free(ssh)
                    close(fd)
                    continuation.resume(throwing: AppError.message("SSH 密码认证失败：\(message)"))
                    return
                }

                self.session = ssh
                self.socketFD = fd
                continuation.resume()
            }
        }
    }

    func execute(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                guard let session = self.session else {
                    continuation.resume(throwing: AppError.notConnected)
                    return
                }
                guard let channel = libssh2_channel_open_session(session) else {
                    continuation.resume(throwing: AppError.message(
                        "打开 SSH 通道失败：\(Self.lastError(session))"
                    ))
                    return
                }
                defer {
                    libssh2_channel_free(channel)
                }
                let execResult = command.withCString { pointer in
                    libssh2_channel_exec(channel, pointer)
                }
                guard execResult == 0 else {
                    continuation.resume(throwing: AppError.message(
                        "执行 SSH 命令失败：\(Self.lastError(session))"
                    ))
                    return
                }

                var output = Data()
                var buffer = [CChar](repeating: 0, count: 16 * 1024)
                while true {
                    let read = buffer.withUnsafeMutableBufferPointer { pointer in
                        libssh2_channel_read(channel, pointer.baseAddress, pointer.count)
                    }
                    if read > 0 {
                        output.append(contentsOf: buffer.prefix(read).map { UInt8(bitPattern: $0) })
                    } else if read == 0 {
                        break
                    } else if read == Int32(LIBSSH2_ERROR_EAGAIN) {
                        continue
                    } else {
                        continuation.resume(throwing: AppError.message(
                            "读取 SSH 输出失败：\(Self.lastError(session))"
                        ))
                        return
                    }
                }
                continuation.resume(returning: String(decoding: output, as: UTF8.self))
            }
        }
    }

    func disconnect() {
        queue.async {
            self.closeLocked()
        }
    }

    private func closeLocked() {
        if let session {
            libssh2_session_disconnect(session, "bye")
            libssh2_session_free(session)
            self.session = nil
        }
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private static func lastError(_ session: OpaquePointer) -> String {
        var message: UnsafeMutablePointer<CChar>?
        var length: Int32 = 0
        let code = libssh2_session_last_error(session, &message, &length, 0)
        if let message {
            return String(cString: message)
        }
        return "libssh2 错误 \(code)"
    }
}
