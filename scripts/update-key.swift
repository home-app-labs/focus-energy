// Home App Labs update signing key.
//
//   swift scripts/update-key.swift            prints the public key, creating the key pair first if there is none
//   swift scripts/update-key.swift sign FILE  prints the signature of FILE, base64
//
// The private key lives in ~/.homeapplabs/update-signing.key and nowhere else. It is never printed.
// Apps carry the public key and install only updates signed with the private one.
// Back the key file up: without it no update can be published for copies already installed.
import CryptoKit
import Foundation

let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".homeapplabs/update-signing.key")

func loadOrCreateKey() throws -> Curve25519.Signing.PrivateKey {
    if let stored = try? String(contentsOf: keyURL, encoding: .utf8),
       let raw = Data(base64Encoded: stored.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    }
    if CommandLine.arguments.count > 1 {
        FileHandle.standardError.write("No signing key at \(keyURL.path). Run this script without arguments to create one.\n".data(using: .utf8)!)
        exit(1)
    }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    FileManager.default.createFile(atPath: keyURL.path, contents: key.rawRepresentation.base64EncodedString().data(using: .utf8),
                                   attributes: [.posixPermissions: 0o600])
    FileHandle.standardError.write("Created a new signing key at \(keyURL.path). Back it up.\n".data(using: .utf8)!)
    return key
}

let key = try loadOrCreateKey()
let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "sign" {
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    print(try key.signature(for: data).base64EncodedString())
} else {
    print(key.publicKey.rawRepresentation.base64EncodedString())
}
