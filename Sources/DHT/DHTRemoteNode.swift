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

import Dispatch

import BTMetainfo

/// DHTRemoteNode represents a remote node.
public struct DHTRemoteNode: Codable, CustomDebugStringConvertible {
    public struct Identifier: Hashable, Codable {
        /// The remote address
        public let address: DHTNetworkAddress
        /// The node's ID
        public let nodeID: NodeID?

        public init(
            address: DHTNetworkAddress,
            nodeID: NodeID?
        ) {
            self.address = address
            self.nodeID = nodeID
        }

        public func isValidNodeID() -> Bool {
            guard let nodeID = self.nodeID else {
                return false
            }

            switch self.address {
            case let .hostPort(host: host, port: _):
                switch host {
                case let .ipv4(address):
                    return address.isValidNodeID(nodeID)
                case let .ipv6(address):
                    return address.isValidNodeID(nodeID)
                case .name:
                    return false
                }
            }
        }
    }

    public enum State {
        case good
        case questionable
        case bad
    }

    public let id: Identifier

    /// The last time a response was received from the remote node
    public private(set) var lastResponse: DispatchTime?
    /// The last time any query was received from the remote node
    public private(set) var lastQuery: DispatchTime?
    /// The number of responses that have effectively timed out since the last successful response
    public private(set) var missingResponses = 0

    static let timeoutInterval: DispatchTimeInterval = DispatchTimeInterval.seconds(15 * 60)

    public var state: State {
        let now = DispatchTime.now()
        if let lastResponse = lastResponse, lastResponse + DHTRemoteNode.timeoutInterval > now {
            return .good
        }
        if let lastQuery = lastQuery, lastResponse != nil, lastQuery + DHTRemoteNode.timeoutInterval > now {
            return .good
        }
        if missingResponses > 2 {
            return .bad
        }
        return .questionable
    }

    public var lastInteraction: DispatchTime? {
        if lastQuery == nil {
            return lastResponse
        }
        if lastResponse == nil {
            return lastQuery
        }
        if let lastResponse = lastResponse, let lastQuery = lastQuery {
            if lastResponse < lastQuery {
                return lastQuery
            } else {
                return lastResponse
            }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }

    /// Designated initializer.
    public init(id: Identifier) {
        self.id = id
    }

    public init(from decoder: Decoder) throws {
        let nodeContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try nodeContainer.decode(Identifier.self, forKey: CodingKeys.id)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: CodingKeys.id)
    }

    public mutating func expectedResponseTimedOut() {
        self.missingResponses += 1
    }

    public mutating func receivedError() {
        self.lastResponse = DispatchTime.now()
        self.missingResponses += 1
    }

    public mutating func receivedResponse() {
        self.lastResponse = DispatchTime.now()
        self.missingResponses -= 1
        self.missingResponses = max(self.missingResponses, 0)
    }

    public mutating func receivedQuery() {
        self.lastQuery = DispatchTime.now()
    }

    public var debugDescription: String {
        // swiftlint:disable line_length
        return "DHTRemoteNode(id: \(id), state: \(state), lastResponse: \(String(describing: lastResponse)), lastQuery: \(String(describing: lastQuery)), missingResponses: \(missingResponses))"
        // swiftlint:enable line_length
    }
}

extension DHTRemoteNode: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }

    public static func == (lhs: DHTRemoteNode, rhs: DHTRemoteNode) -> Bool {
        return lhs.id == rhs.id
    }
}
