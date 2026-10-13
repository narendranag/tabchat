import CryptoKit
import Foundation

/// Name-based UUID (v5, SHA-1). A profile name must map to the same website data store on every
/// launch, otherwise the user would be signed out after each restart.
enum StableUUID {
    private static let namespace = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")! // the standard URL namespace

    static func make(_ name: String) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(Data(("tabchat/" + name).utf8))
        var h = Array(Insecure.SHA1.hash(data: data).prefix(16))
        h[6] = (h[6] & 0x0F) | 0x50
        h[8] = (h[8] & 0x3F) | 0x80
        return UUID(uuid: (
            h[0],
            h[1],
            h[2],
            h[3],
            h[4],
            h[5],
            h[6],
            h[7],
            h[8],
            h[9],
            h[10],
            h[11],
            h[12],
            h[13],
            h[14],
            h[15]
        ))
    }
}
