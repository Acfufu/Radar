import Foundation

final class LocalPhase3HTTPServer: @unchecked Sendable {
    private let process = Process()
    private let root: URL
    private let portFile: URL
    private let countFile: URL
    private let targetFile: URL
    private var port = 0

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        portFile = root.appending(path: "port")
        countFile = root.appending(path: "count")
        targetFile = root.appending(path: "target")
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", Self.script, portFile.path, countFile.path, targetFile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        var discoveredPort: Int?
        for _ in 0..<100 {
            if let text = try? String(contentsOf: portFile, encoding: .utf8), let value = Int(text) {
                discoveredPort = value
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let discoveredPort else {
            stop()
            throw URLError(.cannotConnectToHost)
        }
        port = discoveredPort
    }

    func url(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    var targetWasReached: Bool {
        FileManager.default.fileExists(atPath: targetFile.path)
    }

    func waitForBytesWritten() async throws -> Int {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: countFile, encoding: .utf8), let value = Int(text) {
                return value
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: root)
    }

    private static let script = #"""
import http.server, socketserver, sys, time
port_file, count_file, target_file = sys.argv[1:]
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass
    def do_GET(self):
        if self.path == '/oversize':
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(2*1024*1024)); self.end_headers()
            sent = 0
            try:
                for _ in range(2048):
                    self.wfile.write(b'x'*1024); self.wfile.flush(); sent += 1024; time.sleep(0.001)
            except (BrokenPipeError, ConnectionResetError): pass
            finally: open(count_file,'w').write(str(sent))
        elif self.path == '/redirect':
            self.send_response(302); self.send_header('Location',f'http://127.0.0.1:{self.server.server_address[1]}/target'); self.end_headers()
        else:
            open(target_file,'w').write(self.headers.get('Authorization','')+'|'+self.headers.get('If-None-Match',''))
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b'{}')
with socketserver.TCPServer(('127.0.0.1',0),Handler) as server:
    open(port_file,'w').write(str(server.server_address[1])); server.serve_forever()
"""#
}
