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

import BTMetainfo

/// Resolves a hostname and a port to a DHTNetworkAddress.
public protocol DHTNetworkAddressResolver {
    /// Resolves a hostname and a port to a DHTNetworkAddress.
    func resolve(hostname: String, port: Int) throws -> DHTNetworkAddress?
}

public enum DHTNetworkAddressError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    case unknownHostname
    case unsupported

    public var description: String {
        switch self {
        case .unknownHostname:
            return "Unknown Hostname"
        case .unsupported:
            return "Unsupported"
        }
    }

    public var debugDescription: String {
        switch self {
        case .unknownHostname:
            return "DHTNetworkAddressError.unknownHostname"
        case .unsupported:
            return "DHTNetworkAddressError.unsupported"
        }
    }
}

public enum DHTNetworkAddress: Equatable, Codable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Host: Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
        enum CodingKeys: String, CodingKey {
            case name
            case ipv4
            case ipv6
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let hostname = try container.decodeIfPresent(String.self, forKey: CodingKeys.name) {
                self = Host.name(hostname)
                return
            }

            if let ipv4 = try container.decodeIfPresent(DHTIPv4Address.self, forKey: CodingKeys.ipv4) {
                self = Host.ipv4(ipv4)
                return
            }

            let ipv6 = try container.decode(DHTIPv6Address.self, forKey: CodingKeys.ipv6)
            self = Host.ipv6(ipv6)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .name(hostname):
                try container.encode(hostname, forKey: CodingKeys.name)
            case let .ipv4(ipv4):
                try container.encode(ipv4, forKey: CodingKeys.ipv4)
            case let .ipv6(ipv6):
                try container.encode(ipv6, forKey: CodingKeys.ipv6)
            }
        }

        case name(String)
        case ipv4(DHTIPv4Address)
        case ipv6(DHTIPv6Address)

        public var description: String {
            switch self {
            case let .name(name):
                return name
            case let .ipv4(ipv4Address):
                return ipv4Address.description
            case let .ipv6(ipv6Address):
                return ipv6Address.description
            }
        }

        public var debugDescription: String {
            switch self {
            case let .name(name):
                return "DHTNetworkAddress.Host.name(\(name))"
            case let .ipv4(ipv4Address):
                return "DHTNetworkAddress.Host.ipv4(\(ipv4Address.debugDescription))"
            case let .ipv6(ipv6Address):
                return "DHTNetworkAddress.Host.ipv6(\(ipv6Address.debugDescription))"
            }
        }
    }

    public struct Port: ExpressibleByIntegerLiteral, Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
        public typealias IntegerLiteralType = UInt16

        public let rawValue: IntegerLiteralType

        public init?(_ string: String) {
            guard let port = IntegerLiteralType(string) else {
                return nil
            }
            self.rawValue = port
        }

        public init?(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public init(integerLiteral value: UInt16) {
            self.rawValue = value
        }

        public var description: String {
            return String(rawValue)
        }

        public var debugDescription: String {
            return "DHTNetworkAddress.Port(rawValue: \(rawValue))"
        }
    }

    enum CodingKeys: String, CodingKey {
        case hostPortHost
        case hostPortPort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let host = try container.decode(DHTNetworkAddress.Host.self, forKey: CodingKeys.hostPortHost)
        let port = try container.decode(DHTNetworkAddress.Port.self, forKey: CodingKeys.hostPortPort)

        self = .hostPort(host: host, port: port)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hostPort(host: host, port: port):
            try container.encode(host, forKey: CodingKeys.hostPortHost)
            try container.encode(port, forKey: CodingKeys.hostPortPort)
        }
    }

    case hostPort(host: DHTNetworkAddress.Host, port: DHTNetworkAddress.Port)

    public func makeContactData(addressResolver: DHTNetworkAddressResolver) -> Data? {
        var data = Data()
        switch self {
        case let .hostPort(host: host, port: port):
            switch host {
            case let .name(hostname):
                do {
                    guard let resolvedAddress = try addressResolver.resolve(hostname: hostname, port: Int(port.rawValue)) else {
                        return nil
                    }

                    switch resolvedAddress {
                    case let .hostPort(host: host, port: port):
                        switch host {
                        case .name:
                            assertionFailure("Should not have received back hostname as network address.")
                            return nil
                        case let .ipv4(ipv4):
                            data.append(ipv4.rawData)
                        case let .ipv6(ipv6):
                            data.append(ipv6.rawData)
                        }

                        let bigEndianPort = port.rawValue.bigEndian
                        let portData = withUnsafeBytes(of: bigEndianPort) { Data($0) }
                        data.append(portData)
                        return data
                    }
                } catch {
                    assertionFailure("Unexpected error: \(error)")
                    return nil
                }
            case let .ipv4(ipv4):
                data.append(ipv4.rawData)
            case let .ipv6(ipv6):
                data.append(ipv6.rawData)
            }

            let bigEndianPort = port.rawValue.bigEndian
            let portData = withUnsafeBytes(of: bigEndianPort) { Data($0) }
            data.append(portData)
        }
        return data
    }

    public var description: String {
        switch self {
        case let .hostPort(host: host, port: port):
            return "\(host.description):\(port.description)"
        }
    }

    public var debugDescription: String {
        switch self {
        case let .hostPort(host: host, port: port):
            return "DHTNetworkAddress.hostPort(host: \(host.debugDescription), port: \(port.debugDescription))"
        }
    }
}

public struct DHTIPv4Address: Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public let rawData: Data

    public init?(_ rawData: Data) {
        precondition(rawData.count == 4, "Invalid IPv4 address rawData")
        self.rawData = rawData
    }

    public var description: String {
        return self.rawData.compactMap { byte -> String in
            String(byte, radix: 10)
        }.joined(separator: ".")
    }

    public var debugDescription: String {
        return "DHTIPv4Address(rawData: \(self.description))"
    }
}

extension DHTIPv4Address {
    public func makeNodeID(randomNumber: UInt8 = UInt8.random(in: 0...7)) -> NodeID {
        let crc32cValue = makeCRC32C(randomNumber: randomNumber)

        let randomNodeID = NodeID.random(in: NodeID.min...NodeID.max)
        var validNodeIDData = Data()
        validNodeIDData.append(UInt8((crc32cValue >> 24) & 0xFF))
        validNodeIDData.append(UInt8((crc32cValue >> 16) & 0xFF))
        validNodeIDData.append(UInt8((crc32cValue >> 8) & 0xF8) | UInt8.random(in: 0...7))
        for index in 3..<19 {
            validNodeIDData.append(randomNodeID.value[index])
        }
        validNodeIDData.append(randomNumber)

        guard let nodeID = NodeID(data: validNodeIDData) else {
            preconditionFailure("Could not makeNodeID from: \(self.debugDescription)")
        }

        return nodeID
    }

    public func isValidNodeID(_ nodeID: NodeID) -> Bool {
        if self.isLoopback() || self.isSelfAssigned() || self.isLocalNetwork() {
            return true
        }

        let randomNumber = nodeID.value[19]
        let crc32cValue = makeCRC32C(randomNumber: randomNumber)

        guard nodeID.value[0] == UInt8((crc32cValue >> 24) & 0xFF) else {
            return false
        }

        guard nodeID.value[1] == UInt8((crc32cValue >> 16) & 0xFF) else {
            return false
        }

        guard (nodeID.value[2] & 0xF8) == UInt8((crc32cValue >> 8) & 0xF8) else {
            return false
        }

        return true
    }

    public func isLocalNetwork() -> Bool {
        if self.rawData[0] == 10 {
            return true
        }

        if self.rawData[0] == 172, self.rawData[1] >> 4 == 1 {
            return true
        }

        if self.rawData[0] == 192, self.rawData[1] == 168 {
            return true
        }

        return false
    }

    public func isSelfAssigned() -> Bool {
        return self.rawData[0] == 169 && self.rawData[1] == 254
    }

    public func isLoopback() -> Bool {
        return self.rawData[0] == 127
    }

    private func makeCRC32C(randomNumber: UInt8) -> UInt32 {
        let mask: [UInt8] = [0x03, 0x0F, 0x3F, 0xFF]
        let r = randomNumber & 0x7

        var maskedBytes: [UInt8] = self.rawData.enumerated().map { enumeratedValue in
            let offset = enumeratedValue.offset
            let byte = enumeratedValue.element

            return byte & mask[offset]
        }
        maskedBytes[0] |= r << 5

        return CRC32C(maskedBytes).value
    }
}

public struct DHTIPv6Address: Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public let rawData: Data

    public init?(_ rawData: Data) {
        precondition(rawData.count == 16, "Invalid IPv4 address rawData")

        self.rawData = rawData
    }

    public var description: String {
        var combinedString = ""

        var stringSlice = self.rawData.hexadecimalString[...]
        while true {
            combinedString += stringSlice.prefix(4)
            stringSlice = stringSlice.dropFirst(4)
            if stringSlice.isEmpty {
                break
            }
            combinedString += ":"
        }

        return combinedString
    }

    public var debugDescription: String {
        return "DHTIPv6Address(rawData: \(self.description))"
    }
}

extension DHTIPv6Address {
    public func makeNodeID(randomNumber: UInt8 = UInt8.random(in: 0...7)) -> NodeID {
        let crc32cValue = makeCRC32C(randomNumber: randomNumber)

        let randomNodeID = NodeID.random(in: NodeID.min...NodeID.max)
        var validNodeIDData = Data()
        validNodeIDData.append(UInt8((crc32cValue >> 24) & 0xFF))
        validNodeIDData.append(UInt8((crc32cValue >> 16) & 0xFF))
        validNodeIDData.append(UInt8((crc32cValue >> 8) & 0xF8) | UInt8.random(in: 0...7))
        for index in 3..<19 {
            validNodeIDData.append(randomNodeID.value[index])
        }
        validNodeIDData.append(randomNumber)

        guard let nodeID = NodeID(data: validNodeIDData) else {
            preconditionFailure("Could not makeNodeID from: \(self.debugDescription)")
        }

        return nodeID
    }

    public func isValidNodeID(_ nodeID: NodeID) -> Bool {
        let randomNumber = nodeID.value[19]
        let crc32cValue = makeCRC32C(randomNumber: randomNumber)

        guard nodeID.value[0] == UInt8((crc32cValue >> 24) & 0xFF) else {
            return false
        }

        guard nodeID.value[1] == UInt8((crc32cValue >> 16) & 0xFF) else {
            return false
        }

        guard (nodeID.value[2] & 0xF8) == UInt8((crc32cValue >> 8) & 0xF8) else {
            return false
        }

        return true
    }

    private func makeCRC32C(randomNumber: UInt8) -> UInt32 {
        let mask: [UInt8] = [0x01, 0x03, 0x07, 0x0F, 0x01F, 0x3F, 0x7F, 0xFF]
        let r = randomNumber & 0x7

        var maskedBytes: [UInt8] = self.rawData.prefix(8).enumerated().map { enumeratedValue in
            let offset = enumeratedValue.offset
            let byte = enumeratedValue.element

            return byte & mask[offset]
        }
        maskedBytes[0] |= r << 5

        return CRC32C(maskedBytes).value
    }
}
