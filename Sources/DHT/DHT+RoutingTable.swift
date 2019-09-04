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

import struct Foundation.UUID

import BTMetainfo

extension DHT {
    public struct RoutingTable {
        public let nodeIDPivot: NodeID
        public private(set) var buckets: [Bucket]

        public init(nodeIDPivot: NodeID, maxNodeCountPerBucket: Int) {
            self.nodeIDPivot = nodeIDPivot
            self.buckets = [Bucket(range: NodeID.min...NodeID.max, maxNodeCount: maxNodeCountPerBucket)]
        }

        public func findNearestNeighbors(
            nodeID: NodeID,
            bootstrapNodes: [DHTRemoteNode.Identifier],
            includeAllBootstrapNodes: Bool,
            wantCount: Int = 8
        ) -> [DHTRemoteNode.Identifier] {
            guard var bucketIndex = buckets.firstIndex(where: { $0.range.contains(nodeID) }) else {
                fatalError("Should have found bucket for \(nodeID), \(self)")
            }
            var remoteIDs: [DHTRemoteNode.Identifier] = []
            while remoteIDs.count < wantCount, bucketIndex >= 0 {
                remoteIDs.append(contentsOf: buckets[bucketIndex].prioritizedNodeIDs)
                bucketIndex -= 1
            }

            if includeAllBootstrapNodes {
                remoteIDs.append(contentsOf: bootstrapNodes)
            } else {
                let bootstrapNodesCount = wantCount - remoteIDs.count
                if bootstrapNodesCount > 0 {
                    let nodesToAdd = bootstrapNodes.prefix(bootstrapNodesCount)
                    remoteIDs.append(contentsOf: nodesToAdd)
                }
            }
            return remoteIDs
        }

        public func containsNode(remoteID: DHTRemoteNode.Identifier) -> Bool {
            if let nodeID = remoteID.nodeID {
                guard let bucketIndex = self.buckets.firstIndex(where: { $0.range.contains(nodeID) }) else {
                    preconditionFailure("Should have found bucket for \(nodeID), \(self)")
                }

                return self.buckets[bucketIndex].containsNode(remoteID: remoteID)
            }

            return false
        }

        public mutating func updateQueryReceived(for remoteID: DHTRemoteNode.Identifier) {
            guard let nodeID = remoteID.nodeID else {
                return
            }

            guard let bucketIndex = self.buckets.firstIndex(where: { $0.range.contains(nodeID) }) else {
                preconditionFailure("Should have found bucket for \(nodeID), \(self)")
            }

            self.buckets[bucketIndex].updateQueryReceived(for: remoteID)
        }

        public mutating func updateResponseReceived(for remoteID: DHTRemoteNode.Identifier) {
            guard let nodeID = remoteID.nodeID else {
                return
            }

            guard let bucketIndex = self.buckets.firstIndex(where: { $0.range.contains(nodeID) }) else {
                preconditionFailure("Should have found bucket for \(nodeID), \(self)")
            }

            self.buckets[bucketIndex].updateResponseReceived(for: remoteID)
        }

        public mutating func updateErrorReceived(for remoteID: DHTRemoteNode.Identifier) {
            guard let nodeID = remoteID.nodeID else {
                return
            }

            guard let bucketIndex = self.buckets.firstIndex(where: { $0.range.contains(nodeID) }) else {
                preconditionFailure("Should have found bucket for \(nodeID), \(self)")
            }

            self.buckets[bucketIndex].updateErrorReceived(for: remoteID)
        }

        public mutating func updateResponseTimeout(for remoteID: DHTRemoteNode.Identifier) {
            guard let nodeID = remoteID.nodeID else {
                return
            }

            guard let bucketIndex = self.buckets.firstIndex(where: { $0.range.contains(nodeID) }) else {
                preconditionFailure("Should have found bucket for \(nodeID), \(self)")
            }

            self.buckets[bucketIndex].updateResponseTimeout(for: remoteID)
        }

        public mutating func add(
            nodeWithID remoteID: DHTRemoteNode.Identifier,
            replacingNodeWithID replacingRemoteID: DHTRemoteNode.Identifier?
        ) {
            guard let nodeID = remoteID.nodeID, nodeID != nodeIDPivot else {
                return
            }

            guard let bucketIndex = self.buckets.firstIndex(where: { $0.range.contains(nodeID) }) else {
                preconditionFailure("Should have found bucket for \(nodeID), \(self)")
            }

            guard !self.buckets[bucketIndex].containsNode(remoteID: remoteID) else {
                return
            }

            if self.buckets[bucketIndex].range.contains(nodeIDPivot), self.buckets[bucketIndex].isFull {
                // Add the node to the appropriate bucket
                assert(bucketIndex == buckets.count - 1)

                var (firstBucket, secondBucket) = self.buckets[bucketIndex].splitBucket()
                buckets.removeLast()

                if firstBucket.range.contains(nodeID) {
                    firstBucket.add(nodeWithID: remoteID, replacingNodeWithID: replacingRemoteID)
                } else {
                    assert(secondBucket.range.contains(nodeID))
                    secondBucket.add(nodeWithID: remoteID, replacingNodeWithID: replacingRemoteID)
                }

                if firstBucket.range.contains(nodeIDPivot) {
                    buckets.append(secondBucket)
                    buckets.append(firstBucket)
                } else {
                    buckets.append(firstBucket)
                    buckets.append(secondBucket)
                }
            } else {
                self.buckets[bucketIndex].add(nodeWithID: remoteID, replacingNodeWithID: replacingRemoteID)
            }
        }
    }
}

extension DHT.RoutingTable: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "DHT.RoutingTable(nodeIDPivot: \(nodeIDPivot), buckets: \(buckets))"
    }
}

extension DHT {
    public func addToRoutingTable(
        nodeWithID remoteID: DHTRemoteNode.Identifier,
        completionHandler: @escaping (Result<Bool, Error>) -> Void
    ) {
        switch remoteID.address {
        case let .hostPort(host: host, port: _):
            switch host {
            case .ipv4:
                guard !self.ipv4RoutingTable.containsNode(remoteID: remoteID) else {
                    completionHandler(Result.success(false))
                    return
                }

                guard let nodeID = remoteID.nodeID else {
                    completionHandler(Result.success(false))
                    return
                }

                guard let bucket = self.ipv4RoutingTable.buckets.first(where: { $0.range.contains(nodeID) }) else {
                    preconditionFailure("Should have found bucket for \(nodeID)")
                }

                guard bucket.isFull else {
                    self.ipv4RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: nil)
                    completionHandler(Result.success(true))
                    return
                }

                guard !bucket.range.contains(self.ipv4RoutingTable.nodeIDPivot) else {
                    self.ipv4RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: nil)
                    completionHandler(Result.success(true))
                    return
                }

                guard !bucket.isAllGoodNodes else {
                    completionHandler(Result.success(false))
                    return
                }

                if let firstBadNode = bucket.badNodeRemoteIDs.first {
                    self.ipv4RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: firstBadNode)
                    completionHandler(Result.success(true))
                    return
                }

                let leastRecentlySeenQuestionableRemoteIDs = bucket.leastRecentlySeenQuestionableNodeIDs
                self.findNodeToReplace(
                    remoteIDs: leastRecentlySeenQuestionableRemoteIDs[...]
                ) { [weak self] result in
                    guard let self = self else {
                        completionHandler(Result.success(false))
                        return
                    }

                    switch result {
                    case let .success(remoteIDToReplace):
                        if let remoteIDToReplace = remoteIDToReplace {
                            self.ipv4RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: remoteIDToReplace)
                            completionHandler(Result.success(true))
                        } else {
                            completionHandler(Result.success(false))
                            return
                        }
                    case .failure:
                        completionHandler(Result.success(false))
                        return
                    }
                }
            case .ipv6:
                guard !self.ipv6RoutingTable.containsNode(remoteID: remoteID) else {
                    completionHandler(Result.success(false))
                    return
                }

                guard let nodeID = remoteID.nodeID else {
                    completionHandler(Result.success(false))
                    return
                }

                guard let bucket = self.ipv6RoutingTable.buckets.first(where: { $0.range.contains(nodeID) }) else {
                    preconditionFailure("Should have found bucket for \(nodeID)")
                }

                guard bucket.isFull else {
                    self.ipv6RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: nil)
                    completionHandler(Result.success(true))
                    return
                }

                guard !bucket.range.contains(self.ipv6RoutingTable.nodeIDPivot) else {
                    self.ipv6RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: nil)
                    completionHandler(Result.success(true))
                    return
                }

                guard !bucket.isAllGoodNodes else {
                    completionHandler(Result.success(false))
                    return
                }

                if let firstBadNode = bucket.badNodeRemoteIDs.first {
                    self.ipv6RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: firstBadNode)
                    completionHandler(Result.success(true))
                    return
                }

                let leastRecentlySeenQuestionableRemoteIDs = bucket.leastRecentlySeenQuestionableNodeIDs
                self.findNodeToReplace(
                    remoteIDs: leastRecentlySeenQuestionableRemoteIDs[...]
                ) { [weak self] result in
                    guard let self = self else {
                        completionHandler(Result.success(false))
                        return
                    }

                    switch result {
                    case let .success(remoteIDToReplace):
                        if let remoteIDToReplace = remoteIDToReplace {
                            self.ipv6RoutingTable.add(nodeWithID: remoteID, replacingNodeWithID: remoteIDToReplace)
                            completionHandler(Result.success(true))
                        } else {
                            completionHandler(Result.success(false))
                            return
                        }
                    case .failure:
                        completionHandler(Result.success(false))
                        return
                    }
                }
            case .name:
                completionHandler(Result.success(false))
            }
        }
    }

    private func findNodeToReplace(
        remoteIDs: ArraySlice<DHTRemoteNode.Identifier>,
        completionHandler: @escaping (Result<DHTRemoteNode.Identifier?, Error>) -> Void
    ) {
        guard let remoteID = remoteIDs.first else {
            completionHandler(Result.success(nil))
            return
        }

        let pingOperation = self.makePingOperation(id: UUID().uuidString, remoteID: remoteID)
        pingOperation.pingCompletionBlock = { result in
            defer { self.operations.removeAll(where: { $0.id == pingOperation.id }) }

            switch result {
            case .success:
                self.findNodeToReplace(remoteIDs: remoteIDs.dropFirst(), completionHandler: completionHandler)
                return
            case .failure:
                break
            }

            let secondPingOperation = self.makePingOperation(id: UUID().uuidString, remoteID: remoteID)
            secondPingOperation.pingCompletionBlock = { result in
                defer { self.operations.removeAll(where: { $0.id == secondPingOperation.id }) }

                switch result {
                case .success:
                    self.findNodeToReplace(remoteIDs: remoteIDs.dropFirst(), completionHandler: completionHandler)
                    return
                case .failure:
                    break
                }

                completionHandler(Result.success(remoteID))
            }
            self.operations.append(secondPingOperation)
            secondPingOperation.start()
        }
        self.operations.append(pingOperation)
        pingOperation.start()
    }
}
