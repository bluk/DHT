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

import struct Foundation.Data

import BTMetainfo

extension DHT {
    public class FindNodeOperation: DHTOperation {
        public let id: DHTOperation.ID

        public private(set) var state: State
        public var stateUpdateHandler: ((State) -> Void)?

        public let nodeID: NodeID
        public let want: [Data]?
        public let timeout: DispatchTimeInterval

        public var queryCreatedTransactionHandler: DHT.QueryCreatedTransactionHandler?

        private weak var dht: DHTLocalNode?
        private var currentTransactionID: TransactionID?

        public var findNodeCompletionHandler: ((Result<[DHTRemoteNode.Identifier], Error>) -> Void)?
        public var findNodeQueryResponseHandler: ((DHTRemoteNode.Identifier, Result<KRPCMessage, Error>) -> Void)?

        public private(set) var foundNodes: Set<DHTRemoteNode.Identifier> = []
        public private(set) var alreadyQueriedNodes: Set<DHTRemoteNode.Identifier> = []
        public private(set) var remainingNodesToQuery: [DHTRemoteNode.Identifier]

        public let maxNodesToFind: Int?

        init(
            id: DHTOperation.ID,
            nodeID: NodeID,
            nodesToStartQueryWith: [DHTRemoteNode.Identifier],
            maxNodesToFind: Int?,
            want: [Data]?,
            timeout: DispatchTimeInterval?,
            dht: DHTLocalNode
        ) {
            self.id = id
            self.nodeID = nodeID
            self.maxNodesToFind = maxNodesToFind
            self.want = want
            self.timeout = timeout ?? dht.config.queryTimeout
            self.dht = dht

            self.state = .setup

            self.remainingNodesToQuery = nodesToStartQueryWith.reversed()
        }

        public func start() {
            guard case .setup = self.state else {
                return
            }

            self.transitionState(to: .executing)

            self.attemptFindNode()
        }

        public func attemptFindNode() {
            guard case .executing = self.state else {
                return
            }

            guard let remoteID = self.remainingNodesToQuery.popLast() else {
                let sortedFoundNodes = Array(self.foundNodes).sorted(by: {
                    guard let lhsNodeID = $0.nodeID else {
                        return false
                    }
                    guard let rhsNodeID = $1.nodeID else {
                        return true
                    }
                    return lhsNodeID.distance(from: nodeID) < rhsNodeID.distance(from: nodeID)
                })
                self.findNodeCompletionHandler?(Result.success(sortedFoundNodes))
                self.transitionState(to: .completed)
                return
            }

            guard !self.alreadyQueriedNodes.contains(remoteID) else {
                self.attemptFindNode()
                return
            }

            guard let dht = dht else {
                let error = DHTNodeError.channelNotAvailable
                self.findNodeCompletionHandler?(Result.failure(DHTNodeError.channelNotAvailable))
                self.transitionState(to: .failed(error))
                return
            }

            let args: KRPCArguments
            switch remoteID.address {
            case let .hostPort(host: host, port: _):
                switch host {
                case .ipv4, .name:
                    args = KRPCArguments(nodeID: dht.ipv4RoutingTable.nodeIDPivot, targetID: nodeID, want: self.want)
                case .ipv6:
                    args = KRPCArguments(nodeID: dht.ipv6RoutingTable.nodeIDPivot, targetID: nodeID, want: self.want)
                }
            }

            let transactionID: TransactionID = dht.makeTransactionID()
            let query = KRPCMessage(
                transactionID: transactionID,
                queryMethodName: KRPCMessage.MethodName.findNode,
                arguments: args,
                clientVersion: dht.config.clientVersion,
                isReadOnlyNode: dht.config.isReadOnlyNode
            )

            let queryCompletionHandler: (Result<KRPCMessage, Error>) -> Void = { [weak self] result in
                guard let self = self else {
                    return
                }

                self.findNodeQueryResponseHandler?(remoteID, result)

                switch result {
                case .failure:
                    self.attemptFindNode()
                    return
                case let .success(message):
                    guard message.y == .response else {
                        assertionFailure("Only expected a response message")
                        self.attemptFindNode()
                        return
                    }

                    self.alreadyQueriedNodes.insert(remoteID)
                    self.foundNodes.insert(remoteID)

                    if let maxNodesToFind = self.maxNodesToFind {
                        guard self.foundNodes.count < maxNodesToFind else {
                            let sortedFoundNodes = Array(self.foundNodes).sorted(by: {
                                guard let lhsNodeID = $0.nodeID else {
                                    return false
                                }
                                guard let rhsNodeID = $1.nodeID else {
                                    return true
                                }
                                return lhsNodeID.distance(from: self.nodeID) < rhsNodeID.distance(from: self.nodeID)
                            })
                            self.findNodeCompletionHandler?(Result.success(sortedFoundNodes))
                            self.transitionState(to: .completed)
                            return
                        }
                    }

                    var foundRemoteNodes: [DHTRemoteNode.Identifier] = []
                    if let foundIPv4RemoteNodes = message.r?.foundRemoteIPv4Nodes {
                        foundRemoteNodes.append(contentsOf: foundIPv4RemoteNodes)
                    }
                    if let foundIPv6RemoteNodes = message.r?.foundRemoteIPv6Nodes {
                        foundRemoteNodes.append(contentsOf: foundIPv6RemoteNodes)
                    }
                    guard !foundRemoteNodes.isEmpty else {
                        self.attemptFindNode()
                        return
                    }

                    let newNodes = Set(foundRemoteNodes.filter {
                        if self.alreadyQueriedNodes.contains($0) {
                            return false
                        }

                        switch $0.address {
                        case let .hostPort(host: host, port: _):
                            switch host {
                            case .ipv4:
                                return $0.nodeID != dht.ipv4RoutingTable.nodeIDPivot
                            case .ipv6:
                                return $0.nodeID != dht.ipv6RoutingTable.nodeIDPivot
                            case .name:
                                return false
                            }
                        }
                    })
                    self.remainingNodesToQuery.append(contentsOf: newNodes)
                    self.remainingNodesToQuery.sort(by: {
                        guard let lhsNodeID = $0.nodeID else {
                            return false
                        }
                        guard let rhsNodeID = $1.nodeID else {
                            return true
                        }
                        return lhsNodeID.distance(from: self.nodeID) < rhsNodeID.distance(from: self.nodeID)
                    })

                    self.attemptFindNode()
                }
            }

            self.queryCreatedTransactionHandler?(remoteID, transactionID)

            dht.send(
                message: query,
                to: remoteID,
                queryTimeout: self.timeout,
                queryCompletionHandler: queryCompletionHandler
            ) { _ in
            }
        }

        public func cancel() {
            switch self.state {
            case .setup, .executing:
                break
            case .cancelled, .completed, .failed:
                return
            }

            defer {
                self.findNodeCompletionHandler?(Result.failure(DHTResponseError.cancelled))
                self.transitionState(to: .cancelled)
            }

            guard let transactionID = self.currentTransactionID else {
                preconditionFailure("Expected transactionID")
            }
            guard let dht = self.dht else {
                return
            }

            dht.completeTransaction(
                transactionID: transactionID,
                result: Result.failure(DHTResponseError.cancelled)
            )
        }

        private func transitionState(to newState: DHTOperationState) {
            self.state = newState
            self.stateUpdateHandler?(newState)
        }
    }

    public func makeFindNodeOperation(
        id: DHTOperation.ID,
        nodeID: NodeID,
        nodesToStartQueryWith: [DHTRemoteNode.Identifier],
        maxNodesToFind: Int? = nil,
        want: [Data]? = nil,
        timeout: DispatchTimeInterval? = nil
    ) -> FindNodeOperation {
        return FindNodeOperation(
            id: id,
            nodeID: nodeID,
            nodesToStartQueryWith: nodesToStartQueryWith,
            maxNodesToFind: maxNodesToFind,
            want: want,
            timeout: timeout,
            dht: self
        )
    }
}
