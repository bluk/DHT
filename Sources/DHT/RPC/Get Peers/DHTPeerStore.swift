//  Copyright 2019 Bryant Luk
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import struct Foundation.Data
import struct Foundation.Date

import BTMetainfo

internal final class DHTPeerStore: Codable {
    internal var peers: [InfoHash: [DHTPeer]]

    private enum CodingKeys: String, CodingKey {
        case peers
    }

    private struct PeersCodingKeys: CodingKey {
        var stringValue: String

        var intValue: Int? {
            return nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            return nil
        }
    }

    init() {
        self.peers = [:]
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let peersContainer = try container.nestedContainer(keyedBy: PeersCodingKeys.self, forKey: CodingKeys.peers)

        var decodedPeers: [InfoHash: [DHTPeer]] = [:]
        for key in peersContainer.allKeys {
            let infoHash = InfoHash(data: Data(fromHexEncodedString: key.stringValue)!)!
            var decodedInfoHashPeers: [DHTPeer] = []

            var peersArray = try peersContainer.nestedUnkeyedContainer(forKey: key)
            while !peersArray.isAtEnd {
                decodedInfoHashPeers.append(try peersArray.decode(DHTPeer.self))
            }
            decodedPeers[infoHash] = decodedInfoHashPeers
        }

        self.peers = decodedPeers
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var peersContainer = container.nestedContainer(keyedBy: PeersCodingKeys.self, forKey: CodingKeys.peers)

        for (infoHash, infoHashPeers) in peers {
            let key = infoHash.value.hexadecimalString
            var encodedPeersContainer = peersContainer.nestedUnkeyedContainer(
                forKey: PeersCodingKeys(stringValue: key)!
            )
            try encodedPeersContainer.encode(contentsOf: infoHashPeers)
        }
    }

    func add(_ peer: DHTPeer, for infoHash: InfoHash) {
        if var existingArray = peers[infoHash] {
            existingArray.append(peer)
            peers[infoHash] = existingArray
            return
        }

        let newArray: [DHTPeer] = [peer]
        peers[infoHash] = newArray
    }

    func retrievePeers(for infoHash: InfoHash) -> [DHTPeer] {
        return peers[infoHash, default: []]
    }
}

extension DHTPeerStore: CustomDebugStringConvertible {
    var debugDescription: String {
        return "DHTPeerStore(peers: \(peers))"
    }
}
