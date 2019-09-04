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

// swiftlint:disable file_length

import struct Foundation.Data

import BTMetainfo

public struct KRPCMessage: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case query = "q"
        case response = "r"
        case error = "e"
    }

    public struct MethodName {
        public static let ping: String = "ping"

        public static let findNode: String = "find_node"

        public static let getPeers: String = "get_peers"

        public static let announcePeer: String = "announce_peer"
    }

    // swiftlint:disable identifier_name

    // transactionID
    public var t: Data

    public var y: Kind

    public var v: Data?

    // Error Response

    public var errorCode: Int?
    public var errorMessage: String?

    // Query
    public var q: String?

    public var a: KRPCArguments?

    // Response

    public var r: KRPCArguments?

    // BEP 42 - http://bittorrent.org/beps/bep_0042.html
    public var ip: Data?

    // BEP 43 - http://bittorrent.org/beps/bep_0043.html
    public var ro: Int?

    enum CodingKeys: String, CodingKey {
        case a
        case e
        case ip
        case q
        case r
        case ro
        case t
        case v
        case y
    }

    // swiftlint:enable identifier_name

    public var transactionID: UInt16? {
        guard t.count == 2 else {
            return nil
        }
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { t.copyBytes(to: $0, count: 2) }
        return UInt16(bigEndian: value)
    }

    /// The querying node ID
    public var queryingNodeID: NodeID? {
        guard let nodeID = a?.nodeID else {
            return nil
        }
        return NodeID(data: nodeID)
    }

    /// The response node ID
    public var responseNodeID: NodeID? {
        guard let nodeID = r?.nodeID else {
            return nil
        }
        return NodeID(data: nodeID)
    }

    public var isReadOnlyNode: Bool {
        return ro == 1
    }

    public init(transactionID: UInt16, errorCode: Int, errorMessage: String, clientVersion: Data) {
        var bigEndianTransactionIDCounter = transactionID.bigEndian
        let transactionIDData = Data(bytes: &bigEndianTransactionIDCounter, count: 2)
        self.init(transactionID: transactionIDData, errorCode: errorCode, errorMessage: errorMessage, clientVersion: clientVersion)
    }

    public init(transactionID: Data, errorCode: Int, errorMessage: String, clientVersion: Data) {
        self.t = transactionID
        self.y = .error
        self.v = clientVersion
        self.errorCode = errorCode
        self.errorMessage = errorMessage

        self.q = nil
        self.a = nil
        self.r = nil
        self.ro = nil
    }

    public init(transactionID: UInt16, queryMethodName: String, arguments: KRPCArguments, clientVersion: Data, isReadOnlyNode: Bool) {
        var bigEndianTransactionIDCounter = transactionID.bigEndian
        let transactionIDData = Data(bytes: &bigEndianTransactionIDCounter, count: 2)
        self.init(transactionID: transactionIDData, queryMethodName: queryMethodName, arguments: arguments, clientVersion: clientVersion, isReadOnlyNode: isReadOnlyNode)
    }

    public init(transactionID: Data, queryMethodName: String, arguments: KRPCArguments, clientVersion: Data, isReadOnlyNode: Bool) {
        self.t = transactionID
        self.y = .query
        self.q = queryMethodName
        self.v = clientVersion
        self.a = arguments

        self.errorCode = nil
        self.errorMessage = nil
        self.r = nil
        self.ro = isReadOnlyNode ? 1 : nil
    }

    public init(transactionID: UInt16, responseArguments: KRPCArguments, clientVersion: Data) {
        var bigEndianTransactionIDCounter = transactionID.bigEndian
        let transactionIDData = Data(bytes: &bigEndianTransactionIDCounter, count: 2)
        self.init(transactionID: transactionIDData, responseArguments: responseArguments, clientVersion: clientVersion)
    }

    public init(transactionID: Data, responseArguments: KRPCArguments, clientVersion: Data) {
        self.t = transactionID
        self.y = .response
        self.v = clientVersion
        self.r = responseArguments

        self.errorCode = nil
        self.errorMessage = nil
        self.q = nil
        self.a = nil
        self.ro = nil
    }

    public init(from decoder: Decoder) throws {
        let message = try decoder.container(keyedBy: CodingKeys.self)
        self.y = try message.decode(Kind.self, forKey: CodingKeys.y)
        self.t = try message.decode(Data.self, forKey: CodingKeys.t)
        self.v = try message.decodeIfPresent(Data.self, forKey: CodingKeys.v)

        if message.contains(CodingKeys.e) {
            var errorArr = try message.nestedUnkeyedContainer(forKey: CodingKeys.e)
            if errorArr.count ?? 0 == 2 {
                self.errorCode = try errorArr.decode(Int.self)
                self.errorMessage = try errorArr.decode(String.self)
            } else {
                self.errorCode = nil
                self.errorMessage = nil
            }
        } else {
            self.errorCode = nil
            self.errorMessage = nil
        }

        self.q = try message.decodeIfPresent(String.self, forKey: CodingKeys.q)
        self.a = try message.decodeIfPresent(KRPCArguments.self, forKey: CodingKeys.a)

        self.r = try message.decodeIfPresent(KRPCArguments.self, forKey: CodingKeys.r)

        self.ip = try message.decodeIfPresent(Data.self, forKey: CodingKeys.ip)
        self.ro = try message.decodeIfPresent(Int.self, forKey: CodingKeys.ro)
    }

    public func encode(to encoder: Encoder) throws {
        var message = encoder.container(keyedBy: CodingKeys.self)
        try message.encodeIfPresent(t, forKey: CodingKeys.t)
        try message.encodeIfPresent(y, forKey: CodingKeys.y)
        try message.encodeIfPresent(v, forKey: CodingKeys.v)

        switch y {
        case .error:
            var errorArr = message.nestedUnkeyedContainer(forKey: CodingKeys.e)
            try errorArr.encode(errorCode ?? 0)
            try errorArr.encode(errorMessage ?? "")
        case .query:
            try message.encodeIfPresent(q, forKey: CodingKeys.q)
            try message.encodeIfPresent(a, forKey: CodingKeys.a)
        case .response:
            try message.encodeIfPresent(r, forKey: CodingKeys.r)
        }

        try message.encodeIfPresent(ip, forKey: CodingKeys.ip)
        try message.encodeIfPresent(ro, forKey: CodingKeys.ro)
    }
}

extension KRPCMessage: CustomDebugStringConvertible {
    public var debugDescription: String {
        // swiftlint:disable line_length
        return "KRPCMessage(t: \(t.hexadecimalString), y: \(y), q: \(String(describing: q)), a: \(String(describing: a)), r: \(String(describing: r)), errorCode: \(String(describing: errorCode)), errorMessage: \(String(describing: errorMessage)), ip: \(String(describing: ip)), ro: \(String(describing: ro)), v: \(String(describing: v)))"
        // swiftlint:enable line_length
    }
}

public struct KRPCArguments: Codable, Equatable {
    public var nodeID: Data
    public var targetID: Data?
    public var infoHash: Data?
    public var impliedPort: Int?
    public var port: Int?
    public var token: Data?
    public var nodes: Data?
    public var nodes6: Data?
    // swiftlint:disable discouraged_optional_collection
    public var values: [Data]?
    // swiftlint:enable discouraged_optional_collection
    public var want: [Data]?

    public struct WantValue {
        public static let n4: Data = "n4".data(using: .utf8)!

        public static let n6: Data = "n6".data(using: .utf8)!
    }

    // swiftlint:disable identifier_name

    public var foundPeers: [DHTPeer] {
        guard let values = values else {
            return []
        }

        return values.compactMap { data in
            switch data.count {
            case 6:
                let ipAddressData = data[0..<4]
                let portData = data[4..<6]
                var port: UInt16 = 0
                _ = withUnsafeMutableBytes(of: &port) { portData.copyBytes(to: $0, count: 2) }
                port = UInt16(bigEndian: port)

                guard let ipv4Address = DHTIPv4Address(ipAddressData),
                    let portStruct = DHTNetworkAddress.Port(rawValue: port) else {
                    return nil
                }
                let networkAddress = DHTNetworkAddress.hostPort(host: .ipv4(ipv4Address), port: portStruct)
                return DHTPeer(networkAddress: networkAddress)
            case 18:
                let ipAddressData = data[0..<16]
                let portData = data[16..<18]
                var port: UInt16 = 0
                _ = withUnsafeMutableBytes(of: &port) { portData.copyBytes(to: $0, count: 2) }
                port = UInt16(bigEndian: port)

                guard let ipv6Address = DHTIPv6Address(ipAddressData),
                    let portStruct = DHTNetworkAddress.Port(rawValue: port) else {
                    return nil
                }
                let networkAddress = DHTNetworkAddress.hostPort(host: .ipv6(ipv6Address), port: portStruct)
                return DHTPeer(networkAddress: networkAddress)
            default:
                return nil
            }
        }
    }

    public var foundRemoteIPv4Nodes: [DHTRemoteNode.Identifier] {
        guard let nodes = nodes else {
            return []
        }

        guard nodes.count % 26 == 0 else {
            return []
        }

        var remoteIDs: [DHTRemoteNode.Identifier] = []
        let nodeCount = nodes.count / 26
        for index in 0..<nodeCount {
            let offset = index * 26
            guard let nodeID = NodeID(data: Data(nodes[offset..<offset + 20])) else {
                continue
            }

            let ipAddress = nodes[offset + 20..<offset + 24]
            let portData = nodes[offset + 24..<offset + 26]
            var port: UInt16 = 0
            _ = withUnsafeMutableBytes(of: &port) { portData.copyBytes(to: $0, count: 2) }
            port = UInt16(bigEndian: port)

            guard let ipv4Address = DHTIPv4Address(ipAddress),
                let portStruct = DHTNetworkAddress.Port(rawValue: port) else {
                continue
            }
            let networkAddress = DHTNetworkAddress.hostPort(host: .ipv4(ipv4Address), port: portStruct)
            remoteIDs.append(DHTRemoteNode.Identifier(address: networkAddress, nodeID: nodeID))
        }

        return remoteIDs
    }

    public var foundRemoteIPv6Nodes: [DHTRemoteNode.Identifier] {
        guard let nodes6 = nodes6 else {
            return []
        }

        guard nodes6.count % 38 == 0 else {
            return []
        }

        var remoteIDs: [DHTRemoteNode.Identifier] = []
        let nodeCount = nodes6.count / 38
        for index in 0..<nodeCount {
            let offset = index * 38
            guard let nodeID = NodeID(data: Data(nodes6[offset..<offset + 20])) else {
                continue
            }

            let ipAddressData = nodes6[offset + 20..<offset + 36]
            let portData = nodes6[offset + 36..<offset + 38]
            var port: UInt16 = 0
            _ = withUnsafeMutableBytes(of: &port) { portData.copyBytes(to: $0, count: 2) }
            port = UInt16(bigEndian: port)

            guard let ipv6Address = DHTIPv6Address(ipAddressData),
                let portStruct = DHTNetworkAddress.Port(rawValue: port) else {
                continue
            }
            let networkAddress = DHTNetworkAddress.hostPort(host: .ipv6(ipv6Address), port: portStruct)
            remoteIDs.append(DHTRemoteNode.Identifier(address: networkAddress, nodeID: nodeID))
        }

        return remoteIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case target
        case infoHash = "info_hash"
        case port
        case token
        case impliedPort = "implied_port"
        case nodes
        case nodes6
        case want
        case values
    }

    // swiftlint:enable identifier_name

    public init(
        nodeID: String,
        targetID: String? = nil,
        infoHash: InfoHash? = nil,
        impliedPort: Int? = nil,
        port: Int? = nil,
        token: Data? = nil,
        nodes: Data? = nil,
        nodes6: Data? = nil,
        // swiftlint:disable discouraged_optional_collection
        values: [Data]? = nil,
        // swiftlint:enable discouraged_optional_collection
        want: [Data]? = nil
    ) {
        self.init(
            nodeID: nodeID.data(using: .utf8)!,
            targetID: targetID?.data(using: .utf8),
            infoHash: infoHash?.value,
            impliedPort: impliedPort,
            port: port,
            token: token,
            nodes: nodes,
            nodes6: nodes6,
            values: values,
            want: want
        )
    }

    public init(
        nodeID: NodeID,
        targetID: NodeID? = nil,
        infoHash: InfoHash? = nil,
        impliedPort: Int? = nil,
        port: Int? = nil,
        token: Data? = nil,
        nodes: Data? = nil,
        nodes6: Data? = nil,
        // swiftlint:disable discouraged_optional_collection
        values: [Data]? = nil,
        // swiftlint:enable discouraged_optional_collection
        want: [Data]? = nil
    ) {
        self.init(
            nodeID: nodeID.value,
            targetID: targetID?.value,
            infoHash: infoHash?.value,
            impliedPort: impliedPort,
            port: port,
            token: token,
            nodes: nodes,
            nodes6: nodes6,
            values: values,
            want: want
        )
    }

    public init(
        nodeID: Data,
        targetID: Data? = nil,
        infoHash: Data? = nil,
        impliedPort: Int? = nil,
        port: Int? = nil,
        token: Data? = nil,
        nodes: Data? = nil,
        nodes6: Data? = nil,
        // swiftlint:disable discouraged_optional_collection
        values: [Data]? = nil,
        // swiftlint:enable discouraged_optional_collection
        want: [Data]? = nil
    ) {
        self.nodeID = nodeID
        self.targetID = targetID
        self.infoHash = infoHash
        self.impliedPort = impliedPort
        self.port = port
        self.token = token
        self.nodes = nodes
        self.nodes6 = nodes6
        self.values = values
        self.want = want
    }

    public init(from decoder: Decoder) throws {
        let arguments = try decoder.container(keyedBy: CodingKeys.self)
        self.nodeID = try arguments.decode(Data.self, forKey: CodingKeys.id)
        self.targetID = try arguments.decodeIfPresent(Data.self, forKey: CodingKeys.target)
        self.infoHash = try arguments.decodeIfPresent(Data.self, forKey: CodingKeys.infoHash)
        self.impliedPort = try arguments.decodeIfPresent(Int.self, forKey: CodingKeys.impliedPort)
        self.port = try arguments.decodeIfPresent(Int.self, forKey: CodingKeys.port)
        self.token = try arguments.decodeIfPresent(Data.self, forKey: CodingKeys.token)
        self.nodes = try arguments.decodeIfPresent(Data.self, forKey: CodingKeys.nodes)
        self.nodes6 = try arguments.decodeIfPresent(Data.self, forKey: CodingKeys.nodes6)

        if arguments.allKeys.contains(CodingKeys.values) {
            var valuesContainer = try arguments.nestedUnkeyedContainer(forKey: CodingKeys.values)
            var values: [Data] = []
            while !valuesContainer.isAtEnd {
                let val = try valuesContainer.decode(Data.self)
                values.append(val)
            }
            self.values = values.isEmpty ? nil : values
        } else {
            self.values = nil
        }

        if arguments.allKeys.contains(CodingKeys.want) {
            var wantContainer = try arguments.nestedUnkeyedContainer(forKey: CodingKeys.want)
            var want: [Data] = []
            while !wantContainer.isAtEnd {
                let val = try wantContainer.decode(Data.self)
                want.append(val)
            }
            self.want = want.isEmpty ? nil : want
        } else {
            self.want = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var arguments = encoder.container(keyedBy: CodingKeys.self)
        try arguments.encode(nodeID, forKey: CodingKeys.id)
        try arguments.encodeIfPresent(targetID, forKey: CodingKeys.target)
        try arguments.encodeIfPresent(infoHash, forKey: CodingKeys.infoHash)
        try arguments.encodeIfPresent(impliedPort, forKey: CodingKeys.impliedPort)
        try arguments.encodeIfPresent(port, forKey: CodingKeys.port)
        try arguments.encodeIfPresent(token, forKey: CodingKeys.token)
        try arguments.encodeIfPresent(nodes, forKey: CodingKeys.nodes)
        try arguments.encodeIfPresent(nodes6, forKey: CodingKeys.nodes6)
        if let values = values {
            var nestedValuesContainer = arguments.nestedUnkeyedContainer(forKey: CodingKeys.values)
            for val in values {
                try nestedValuesContainer.encode(val)
            }
        }
        if let want = want {
            var nestedWantContainer = arguments.nestedUnkeyedContainer(forKey: CodingKeys.want)
            for val in want {
                try nestedWantContainer.encode(val)
            }
        }
    }
}

extension KRPCArguments: CustomDebugStringConvertible {
    public var debugDescription: String {
        // swiftlint:disable line_length
        return "KRPCArguments(nodeID: \(nodeID.hexadecimalString), targetID: \(targetID?.hexadecimalString ?? ""), infoHash: \(infoHash?.hexadecimalString ?? ""), impliedPort: \(impliedPort ?? -1), port: \(port ?? -1), token: \(token?.hexadecimalString ?? ""), nodes: \(nodes?.hexadecimalString ?? ""), nodes6: \(nodes6?.hexadecimalString ?? ""), values: \((values ?? []).compactMap { $0.hexadecimalString }), want: \(String(describing: want)))"
        // swiftlint:enable line_length
    }
}
