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

extension DHT {
    public class GetPeersOperation: DHTOperation {
        public let id: DHTOperation.ID

        public private(set) var state: State
        public var stateUpdateHandler: ((State) -> Void)?

        public let infoHash: InfoHash
        public let shouldAnnounce: Bool
        public let torrentPort: Int?
        public let timeout: DispatchTimeInterval

        public var queryCreatedTransactionHandler: DHT.QueryCreatedTransactionHandler?

        private weak var dht: DHTLocalNode?
        private var currentTransactionID: TransactionID?

        public var getPeersCompletionHandler: ((Result<Set<DHTPeer>, Error>) -> Void)?
        public var getPeersQueryResponseHandler: ((DHTRemoteNode.Identifier, Result<KRPCMessage, Error>) -> Void)?
        public var announceQueryResponseHandler: ((DHTRemoteNode.Identifier, Result<KRPCMessage, Error>) -> Void)?

        public private(set) var foundPeers: Set<DHTPeer> = []
        public private(set) var alreadyQueriedNodes: Set<DHTRemoteNode.Identifier> = []
        public private(set) var remainingNodesToQuery: [DHTRemoteNode.Identifier]

        public let maxNodesToGetPeersFrom: Int
        public private(set) var nodesReceivedPeersFrom: Int = 0
        public let shouldVerifyNodeIDs: Bool

        init(
            id: DHTOperation.ID,
            infoHash: InfoHash,
            nodesToStartQueryWith: [DHTRemoteNode.Identifier],
            shouldAnnounce: Bool,
            torrentPort: Int?,
            maxNodesToGetPeersFrom: Int,
            shouldVerifyNodeIDs: Bool,
            timeout: DispatchTimeInterval? = nil,
            dht: DHTLocalNode
        ) {
            self.id = id
            self.infoHash = infoHash
            self.shouldAnnounce = shouldAnnounce
            self.torrentPort = torrentPort
            self.maxNodesToGetPeersFrom = maxNodesToGetPeersFrom
            self.shouldVerifyNodeIDs = shouldVerifyNodeIDs
            self.state = .setup
            self.timeout = timeout ?? dht.config.queryTimeout
            self.dht = dht

            self.remainingNodesToQuery = nodesToStartQueryWith.reversed()
        }

        public func start() {
            guard case .setup = self.state else {
                return
            }

            self.transitionState(to: .executing)

            self.attemptGetPeers()
        }

        private func attemptGetPeers() {
            guard case .executing = self.state else {
                return
            }

            guard let remoteID = self.remainingNodesToQuery.popLast() else {
                self.getPeersCompletionHandler?(Result.success(self.foundPeers))
                self.transitionState(to: .completed)
                return
            }

            guard self.nodesReceivedPeersFrom < self.maxNodesToGetPeersFrom else {
                self.getPeersCompletionHandler?(Result.success(self.foundPeers))
                self.transitionState(to: .completed)
                return
            }

            guard !self.alreadyQueriedNodes.contains(remoteID) else {
                self.attemptGetPeers()
                return
            }

            guard let dht = dht else {
                let error = DHTNodeError.channelNotAvailable
                self.getPeersCompletionHandler?(Result.failure(DHTNodeError.channelNotAvailable))
                self.transitionState(to: .failed(error))
                return
            }

            let args: KRPCArguments
            switch remoteID.address {
            case let .hostPort(host: host, port: _):
                switch host {
                case .ipv4:
                    args = KRPCArguments(nodeID: dht.ipv4RoutingTable.nodeIDPivot, infoHash: infoHash)
                case .ipv6:
                    args = KRPCArguments(nodeID: dht.ipv6RoutingTable.nodeIDPivot, infoHash: infoHash)
                case .name:
                    args = KRPCArguments(nodeID: dht.ipv4RoutingTable.nodeIDPivot, infoHash: infoHash)
                }
            }

            let transactionID: TransactionID = dht.makeTransactionID()
            let query = KRPCMessage(
                transactionID: transactionID,
                queryMethodName: KRPCMessage.MethodName.getPeers,
                arguments: args,
                clientVersion: dht.config.clientVersion,
                isReadOnlyNode: dht.config.isReadOnlyNode
            )

            let queryCompletionHandler: (Result<KRPCMessage, Error>) -> Void = { [weak self] result in
                guard let self = self else {
                    return
                }

                guard let dht = self.dht else {
                    let error = DHTNodeError.channelNotAvailable
                    self.getPeersCompletionHandler?(Result.failure(DHTNodeError.channelNotAvailable))
                    self.transitionState(to: .failed(error))
                    return
                }

                self.getPeersQueryResponseHandler?(remoteID, result)

                switch result {
                case .failure:
                    self.attemptGetPeers()
                    return
                case let .success(message):
                    guard message.y == .response else {
                        assertionFailure("Only expected a response message")
                        self.attemptGetPeers()
                        return
                    }

                    self.alreadyQueriedNodes.insert(remoteID)

                    defer { self.attemptGetPeers() }

                    if let foundRemoteNodes = message.r?.foundRemoteIPv4Nodes, !foundRemoteNodes.isEmpty {
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
                                    assertionFailure("Should never occur")
                                    return false
                                }
                            }
                        })
                        self.remainingNodesToQuery.append(contentsOf: newNodes)
                    }

                    if let foundRemoteNodes = message.r?.foundRemoteIPv6Nodes, !foundRemoteNodes.isEmpty {
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
                                    assertionFailure("Should never occur")
                                    return false
                                }
                            }
                        })
                        self.remainingNodesToQuery.append(contentsOf: newNodes)
                    }

                    self.remainingNodesToQuery.sort(by: {
                        guard let lhsNodeID = $0.nodeID else {
                            return false
                        }
                        guard let rhsNodeID = $1.nodeID else {
                            return true
                        }
                        return lhsNodeID.distance(from: self.infoHash) < rhsNodeID.distance(from: self.infoHash)
                    })

                    if let foundPeers = message.r?.foundPeers, !foundPeers.isEmpty {
                        self.foundPeers.formUnion(foundPeers)

                        let isValidNode = !self.shouldVerifyNodeIDs || remoteID.isValidNodeID()
                        guard isValidNode else {
                            return
                        }

                        self.nodesReceivedPeersFrom += 1

                        guard let token = message.r?.token, self.shouldAnnounce else {
                            return
                        }

                        let args: KRPCArguments
                        switch remoteID.address {
                        case let .hostPort(host: host, port: _):
                            switch host {
                            case .ipv4, .name:
                                args = KRPCArguments(
                                    nodeID: dht.ipv4RoutingTable.nodeIDPivot,
                                    infoHash: self.infoHash,
                                    impliedPort: (self.torrentPort == nil) ? 1 : nil,
                                    port: self.torrentPort ?? 0,
                                    token: token
                                )
                            case .ipv6:
                                args = KRPCArguments(
                                    nodeID: dht.ipv6RoutingTable.nodeIDPivot,
                                    infoHash: self.infoHash,
                                    impliedPort: (self.torrentPort == nil) ? 1 : nil,
                                    port: self.torrentPort ?? 0,
                                    token: token
                                )
                            }
                        }

                        let transactionID: TransactionID = dht.makeTransactionID()
                        let announce = KRPCMessage(
                            transactionID: transactionID,
                            queryMethodName: KRPCMessage.MethodName.announcePeer,
                            arguments: args,
                            clientVersion: dht.config.clientVersion,
                            isReadOnlyNode: dht.config.isReadOnlyNode
                        )

                        let queryCompletionHandler: (Result<KRPCMessage, Error>) -> Void = { result in
                            self.announceQueryResponseHandler?(remoteID, result)
                        }

                        self.queryCreatedTransactionHandler?(remoteID, transactionID)

                        dht.send(
                            message: announce,
                            to: remoteID,
                            queryTimeout: self.timeout,
                            queryCompletionHandler: queryCompletionHandler
                        ) { _ in
                        }
                    }
                }
            }

            self.queryCreatedTransactionHandler?(remoteID, transactionID)

            dht.send(
                message: query,
                to: remoteID,
                queryTimeout: timeout,
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
                self.getPeersCompletionHandler?(Result.failure(DHTResponseError.cancelled))
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

    public func makeGetPeersOperation(
        id: DHTOperation.ID,
        infoHash: InfoHash,
        nodesToStartQueryWith: [DHTRemoteNode.Identifier],
        shouldAnnounce: Bool = false,
        torrentPort: Int? = nil,
        maxNodesToGetPeersFrom: Int = 8,
        shouldVerifyNodeIDs: Bool = true,
        timeout: DispatchTimeInterval? = nil
    ) -> GetPeersOperation {
        return GetPeersOperation(
            id: id,
            infoHash: infoHash,
            nodesToStartQueryWith: nodesToStartQueryWith,
            shouldAnnounce: shouldAnnounce,
            torrentPort: torrentPort,
            maxNodesToGetPeersFrom: maxNodesToGetPeersFrom,
            shouldVerifyNodeIDs: shouldVerifyNodeIDs,
            timeout: timeout,
            dht: self
        )
    }
}
