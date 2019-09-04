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

import enum Dispatch.DispatchTimeInterval
import struct Foundation.Data

import BTMetainfo

extension DHT {
    /// Provides the Node Configuration.
    public struct Config {
        /// The local IPv4 node ID
        public var ipv4NodeID: NodeID
        /// The local IPv6 node ID
        public var ipv6NodeID: NodeID
        /// The client version identifier
        public var clientVersion: Data
        /// The amount of time before a query without a response is considered timed out
        public var queryTimeout: DispatchTimeInterval
        /// If the node is read only
        public var isReadOnlyNode: Bool
        /// The maximum number of nodes in a routing table bucket.
        public var maxNodeCountPerBucket: Int

        /// Designated initializer.
        public init(
            ipv4NodeID: NodeID,
            ipv6NodeID: NodeID,
            clientVersion: Data,
            queryTimeout: DispatchTimeInterval = DispatchTimeInterval.seconds(30),
            isReadOnlyNode: Bool = false,
            maxNodeCountPerBucket: Int = 8
        ) {
            self.ipv4NodeID = ipv4NodeID
            self.ipv6NodeID = ipv6NodeID
            self.clientVersion = clientVersion
            self.queryTimeout = queryTimeout
            self.isReadOnlyNode = isReadOnlyNode
            self.maxNodeCountPerBucket = maxNodeCountPerBucket
        }
    }
}

extension DHT.Config: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "DHT.Config(ipv4NodeID: \(ipv4NodeID), ipv6NodeID: \(ipv6NodeID), clientVersion: \(clientVersion), queryTimeout: \(queryTimeout), isReadOnlyNode: \(isReadOnlyNode))"
    }
}
