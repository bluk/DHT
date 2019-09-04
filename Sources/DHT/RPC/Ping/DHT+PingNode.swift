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

extension DHT {
    public class PingOperation: DHTOperation {
        public let id: DHTOperation.ID

        public private(set) var state: State
        public var stateUpdateHandler: ((State) -> Void)?

        public let remoteID: DHTRemoteNode.Identifier
        public let timeout: DispatchTimeInterval

        public var queryCreatedTransactionHandler: DHT.QueryCreatedTransactionHandler?

        private weak var dht: DHTLocalNode?
        private var transactionID: TransactionID?

        public var pingCompletionBlock: ((Result<Void, Error>) -> Void)?

        init(
            id: DHTOperation.ID,
            remoteID: DHTRemoteNode.Identifier,
            timeout: DispatchTimeInterval? = nil,
            dht: DHTLocalNode
        ) {
            self.id = id
            self.state = .setup
            self.remoteID = remoteID
            self.timeout = timeout ?? dht.config.queryTimeout
            self.dht = dht
        }

        public func start() {
            guard case .setup = self.state else {
                return
            }

            guard let dht = self.dht else {
                let error = DHTNodeError.channelNotAvailable
                self.pingCompletionBlock?(Result.failure(DHTNodeError.channelNotAvailable))
                self.transitionState(to: .failed(error))
                return
            }

            self.transitionState(to: .executing)

            let transactionID = dht.makeTransactionID()
            self.transactionID = transactionID

            let args: KRPCArguments
            switch remoteID.address {
            case let .hostPort(host: host, port: _):
                switch host {
                case .ipv4, .name:
                    args = KRPCArguments(nodeID: dht.ipv4RoutingTable.nodeIDPivot)
                case .ipv6:
                    args = KRPCArguments(nodeID: dht.ipv6RoutingTable.nodeIDPivot)
                }
            }
            let query = KRPCMessage(
                transactionID: transactionID,
                queryMethodName: KRPCMessage.MethodName.ping,
                arguments: args,
                clientVersion: dht.config.clientVersion,
                isReadOnlyNode: dht.config.isReadOnlyNode
            )

            let queryCompletionHandler: (Result<KRPCMessage, Error>) -> Void = { result in
                switch self.state {
                case .setup:
                    preconditionFailure("Unexpected state")
                case .executing:
                    break
                case .cancelled, .failed, .completed:
                    return
                }

                switch result {
                case let .success(message):
                    switch message.y {
                    case .response:
                        self.pingCompletionBlock?(Result.success(()))
                        self.transitionState(to: .completed)
                        return
                    case .error, .query:
                        assertionFailure("Should not have encounted this code path")
                        let error = DHTResponseError.errorResponse(message)
                        self.pingCompletionBlock?(Result.failure(error))
                        self.transitionState(to: .failed(error))
                        return
                    }
                case let .failure(error):
                    self.pingCompletionBlock?(Result.failure(error))
                    self.transitionState(to: .failed(error))
                    return
                }
            }

            self.queryCreatedTransactionHandler?(remoteID, transactionID)

            dht.send(
                message: query,
                to: self.remoteID,
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
                self.pingCompletionBlock?(Result.failure(DHTResponseError.cancelled))
                self.transitionState(to: .cancelled)
            }

            guard let transactionID = transactionID else {
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

    public func makePingOperation(
        id: DHTOperation.ID,
        remoteID: DHTRemoteNode.Identifier,
        timeout: DispatchTimeInterval? = nil
    ) -> PingOperation {
        return PingOperation(id: id, remoteID: remoteID, timeout: timeout, dht: self)
    }
}
