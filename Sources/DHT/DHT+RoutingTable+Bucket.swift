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

import struct Dispatch.DispatchTime

import BTMetainfo

extension DHT.RoutingTable {
    public struct Bucket {
        public let range: ClosedRange<NodeID>
        public private(set) var nodes: [DHTRemoteNode]
        public let maxNodeCount: Int
        public private(set) var lastChanged: DispatchTime

        public var isFull: Bool {
            return nodes.count >= maxNodeCount
        }

        public var isAllGoodNodes: Bool {
            return nodes.allSatisfy { node in node.state == DHTRemoteNode.State.good }
        }

        public var badNodeRemoteIDs: [DHTRemoteNode.Identifier] {
            return nodes.filter { node in node.state == DHTRemoteNode.State.bad }.map { $0.id }
        }

        public var leastRecentlySeenQuestionableNodeIDs: [DHTRemoteNode.Identifier] {
            return nodes.filter { node in node.state == .questionable }
                .sorted(by: { firstNode, secondNode in
                    if firstNode.lastInteraction == nil, secondNode.lastInteraction != nil {
                        return true
                    }
                    if secondNode.lastInteraction == nil, firstNode.lastInteraction != nil {
                        return false
                    }
                    if let firstNodeInteraction = firstNode.lastInteraction,
                        let secondNodeInteraction = secondNode.lastInteraction {
                        return firstNodeInteraction < secondNodeInteraction
                    }
                    return false
                })
                .map { $0.id }
        }

        public var prioritizedNodeIDs: [DHTRemoteNode.Identifier] {
            return nodes
                .filter { $0.state == .good || $0.state == .questionable }
                .sorted(by: { firstNode, secondNode in
                    switch (firstNode.state, secondNode.state) {
                    case (.good, .questionable):
                        return true
                    case (.questionable, .good):
                        return false
                    default:
                        return false
                    }
                })
                .map { $0.id }
        }

        public init(
            range: ClosedRange<NodeID>,
            maxNodeCount: Int
        ) {
            self.range = range
            self.maxNodeCount = maxNodeCount
            self.nodes = []
            self.nodes.reserveCapacity(maxNodeCount)
            self.lastChanged = DispatchTime.now()
        }

        public mutating func updateQueryReceived(for remoteID: DHTRemoteNode.Identifier) {
            guard let index = self.nodes.firstIndex(where: { $0.id == remoteID }) else {
                return
            }
            self.nodes[index].receivedQuery()
        }

        public mutating func updateResponseReceived(for remoteID: DHTRemoteNode.Identifier) {
            guard let index = self.nodes.firstIndex(where: { $0.id == remoteID }) else {
                return
            }
            self.nodes[index].receivedResponse()
        }

        public mutating func updateErrorReceived(for remoteID: DHTRemoteNode.Identifier) {
            guard let index = self.nodes.firstIndex(where: { $0.id == remoteID }) else {
                return
            }
            self.nodes[index].receivedError()
        }

        public mutating func updateResponseTimeout(for remoteID: DHTRemoteNode.Identifier) {
            guard let index = self.nodes.firstIndex(where: { $0.id == remoteID }) else {
                return
            }
            self.nodes[index].expectedResponseTimedOut()
        }

        public mutating func add(
            nodeWithID remoteID: DHTRemoteNode.Identifier,
            replacingNodeWithID replacingRemoteID: DHTRemoteNode.Identifier?
        ) {
            assert({
                if let nodeID = remoteID.nodeID {
                    return self.range.contains(nodeID)
                }
                return false
            }())

            if let replacingRemoteID = replacingRemoteID {
                assert({
                    if let nodeID = replacingRemoteID.nodeID {
                        return self.range.contains(nodeID)
                    }
                    return false
                }())
                self.nodes.removeAll(where: { $0.id == replacingRemoteID })
            }

            guard self.nodes.count < self.maxNodeCount else {
                return
            }

            self.nodes.append(DHTRemoteNode(id: remoteID))
            self.lastChanged = DispatchTime.now()
        }

        public func splitBucket() -> (DHT.RoutingTable.Bucket, DHT.RoutingTable.Bucket) {
            let middle = range.upperBound.middle(from: range.lowerBound)
            var lowerBucket = DHT.RoutingTable.Bucket(
                range: range.lowerBound...middle.prev(),
                maxNodeCount: self.maxNodeCount
            )
            var upperBucket = DHT.RoutingTable.Bucket(
                range: middle...range.upperBound,
                maxNodeCount: self.maxNodeCount
            )

            for node in nodes {
                guard let nodeID = node.id.nodeID else {
                    preconditionFailure("Node did not have a nodeID: \(node)")
                }
                if lowerBucket.range.contains(nodeID) {
                    lowerBucket.nodes.append(node)
                } else {
                    upperBucket.nodes.append(node)
                }
            }

            return (lowerBucket, upperBucket)
        }

        public func containsNode(remoteID: DHTRemoteNode.Identifier) -> Bool {
            return self.nodes.contains { $0.id == remoteID }
        }
    }
}

extension DHT.RoutingTable.Bucket: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "DHT.RoutingTable.Bucket(range: \(range), nodes: \(nodes), maxNodeCount: \(maxNodeCount), lastChanged: \(lastChanged))"
    }
}

extension DHT.RoutingTable.Bucket: Equatable {
    public static func == (lhs: DHT.RoutingTable.Bucket, rhs: DHT.RoutingTable.Bucket) -> Bool {
        return lhs.range == rhs.range && lhs.nodes == rhs.nodes
    }
}
