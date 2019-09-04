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

/// Channel declares methods for how messages are written back to the channel.
public protocol DHTChannel {
    func send(
        _ message: KRPCMessage,
        to networkAddress: DHTNetworkAddress,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    )
}

/// Node errors.
public enum DHTNodeError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    case channelNotAvailable
    case receivedResponseFromUnknownAddress
    case receivedResponseWithUnexpectedNodeID
    case receivedMalformedMessage(KRPCMessage)

    public var description: String {
        switch self {
        case .channelNotAvailable:
            return "Channel not available"
        case .receivedResponseFromUnknownAddress:
            return "Received response from unknown address"
        case .receivedResponseWithUnexpectedNodeID:
            return "Received response with unexpected node ID"
        case let .receivedMalformedMessage(message):
            return "Received malformed message: \(message)"
        }
    }

    public var debugDescription: String {
        switch self {
        case .channelNotAvailable:
            return "DHTNodeError.channelNotAvailable"
        case .receivedResponseFromUnknownAddress:
            return "DHTNodeError.receivedResponseFromUnknownAddress"
        case .receivedResponseWithUnexpectedNodeID:
            return "DHTNodeError.receivedResponseWithUnexpectedNodeID"
        case let .receivedMalformedMessage(message):
            return "DHTNodeError.receivedMalformedMessage(message: \(message))"
        }
    }
}

public enum DHTResponseError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    case errorResponse(KRPCMessage)
    case timeout
    case cancelled

    public var description: String {
        switch self {
        case .errorResponse:
            return "Error response"
        case .timeout:
            return "Timeout"
        case .cancelled:
            return "Cancelled"
        }
    }

    public var debugDescription: String {
        switch self {
        case let .errorResponse(message):
            return "DHTResponseError.errorResponse(message: \(message))"
        case .timeout:
            return "DHTResponseError.timeout"
        case .cancelled:
            return "DHTResponseError.cancelled"
        }
    }
}

public protocol DHTLocalNode: AnyObject {
    var config: DHT.Config { get }

    var ipv4RoutingTable: DHT.RoutingTable { get }

    var ipv6RoutingTable: DHT.RoutingTable { get }

    var addressResolver: DHTNetworkAddressResolver { get }

    func makeTransactionID() -> DHT.TransactionID

    func completeTransaction(transactionID: DHT.TransactionID, result: Result<KRPCMessage, Error>)

    func send(
        message: KRPCMessage,
        to remoteID: DHTRemoteNode.Identifier,
        queryTimeout: DispatchTimeInterval?,
        queryCompletionHandler: ((Result<KRPCMessage, Error>) -> Void)?,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    )
}

/// DHTNode listens for DHT requests.
public final class DHT: DHTLocalNode {
    public typealias TransactionID = UInt16

    public typealias QueryCreatedTransactionHandler = (DHTRemoteNode.Identifier, TransactionID) -> Void

    // Be careful about making channel weak

    public let config: DHT.Config
    public let addressResolver: DHTNetworkAddressResolver
    public let queue: DispatchQueue
    public let remoteQueryMessageHandlers: [DHTRemoteQueryMessageHandler]

    public var channel: DHTChannel?

    public var ipv4RoutingTable: RoutingTable {
        didSet {
            self.ipv4RoutingTableUpdateHandler?(self.ipv4RoutingTable)
        }
    }

    public var ipv6RoutingTable: RoutingTable {
        didSet {
            self.ipv6RoutingTableUpdateHandler?(self.ipv6RoutingTable)
        }
    }

    public var ipv4RoutingTableUpdateHandler: ((RoutingTable) -> Void)?
    public var ipv6RoutingTableUpdateHandler: ((RoutingTable) -> Void)?

    public var secretTokens: (InfoHash, InfoHash) {
        didSet {
            self.secretTokensUpdateHandler?(self.secretTokens.0, self.secretTokens.1)
        }
    }

    public var secretTokensUpdateHandler: ((InfoHash, InfoHash) -> Void)?

    /// The outstanding transactions for this node
    public var transactions: [Transaction?]
    private var transactionIDCounter: TransactionID

    public var transactionCreatedHandler: ((Transaction) -> Void)?

    public var transactionCompletedHandler: ((Transaction, Result<KRPCMessage, Error>) -> Void)?

    internal var operations: [DHTOperation] = []

    /// Designated initializer.
    public init(
        config: DHT.Config,
        addressResolver: DHTNetworkAddressResolver,
        queue: DispatchQueue,
        remoteQueryMessageHandlers: [DHTRemoteQueryMessageHandler] = [
            DHTPingQueryMessageHandler(),
            DHTFindNodeQueryMessageHandler(),
        ]
    ) {
        self.config = config
        self.addressResolver = addressResolver
        self.queue = queue
        self.remoteQueryMessageHandlers = remoteQueryMessageHandlers
        self.transactions = [Transaction?](repeating: nil, count: Int(TransactionID.max) + 1)
        self.transactionIDCounter = TransactionID.random(in: TransactionID.min...TransactionID.max)
        self.ipv4RoutingTable = RoutingTable(
            nodeIDPivot: config.ipv4NodeID,
            maxNodeCountPerBucket: self.config.maxNodeCountPerBucket
        )
        self.ipv6RoutingTable = RoutingTable(
            nodeIDPivot: config.ipv6NodeID,
            maxNodeCountPerBucket: self.config.maxNodeCountPerBucket
        )
        let secretToken = InfoHash.random(in: InfoHash.min..<InfoHash.max)
        self.secretTokens = (secretToken, secretToken)
    }

    /// Resolves a transaction and removes it from the tracked transactions.
    public func completeTransaction(transactionID: TransactionID, result: Result<KRPCMessage, Error>) {
        guard let transaction = self.transactions[Int(transactionID)] else {
            return
        }

        transaction.timeoutWorkItem.cancel()
        transaction.completionHandler(result)
        self.transactions[Int(transactionID)] = nil
        self.transactionCompletedHandler?(transaction, result)
    }

    /// Cancels any outstanding timers owned by the node.
    public func cancel() {
        for transactionID in TransactionID.min..<TransactionID.max {
            self.completeTransaction(
                transactionID: transactionID,
                result: Result<KRPCMessage, Error>.failure(DHTResponseError.cancelled)
            )
        }
    }

    private func received(
        response: KRPCMessage,
        from remoteAddress: DHTNetworkAddress,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        assert(response.y == .response)
        guard let nodeID = response.responseNodeID else {
            let errorResponse = KRPCMessage(
                transactionID: response.t,
                errorCode: 203,
                errorMessage: "Protocol Error: Missing response argument id",
                clientVersion: self.config.clientVersion
            )
            let remoteID = DHTRemoteNode.Identifier(address: remoteAddress, nodeID: response.responseNodeID)
            self.send(message: errorResponse, to: remoteID, completionHandler: completionHandler)
            return
        }

        guard let transactionID = response.transactionID,
            let transaction = transactions[Int(transactionID)] else {
            // TODO: In the future, should add to a "address sent a bad packet" list to eventually filter it out
            let errorResponse = KRPCMessage(
                transactionID: response.t,
                errorCode: 203,
                errorMessage: "Protocol Error: Response is not for known query",
                clientVersion: self.config.clientVersion
            )
            let remoteID = DHTRemoteNode.Identifier(address: remoteAddress, nodeID: response.responseNodeID)
            self.send(message: errorResponse, to: remoteID, completionHandler: completionHandler)
            return
        }

        guard transaction.remoteID.address == remoteAddress else {
            // Impersonator? Outdated info?
            completionHandler(Result.failure(DHTNodeError.receivedResponseFromUnknownAddress))
            return
        }

        // If this is a bootstrap node, then the node will be without an ID
        if let remoteNodeID = transaction.remoteID.nodeID,
            remoteNodeID != nodeID {
            completionHandler(Result.failure(DHTNodeError.receivedResponseWithUnexpectedNodeID))
            return
        }

        self.completeTransaction(transactionID: transactionID, result: Result<KRPCMessage, Error>.success(response))

        completionHandler(Result.success(()))
    }

    /// Notifies the node it received a query.
    private func received(
        query: KRPCMessage,
        from remoteAddress: DHTNetworkAddress,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !self.config.isReadOnlyNode else {
            completionHandler(Result.success(()))
            return
        }

        assert(query.y == .query)
        guard let nodeID = query.queryingNodeID else {
            let errorResponse = KRPCMessage(
                transactionID: query.t,
                errorCode: 203,
                errorMessage: "Protocol Error: Missing query argument id",
                clientVersion: self.config.clientVersion
            )
            let remoteID = DHTRemoteNode.Identifier(address: remoteAddress, nodeID: query.queryingNodeID)
            self.send(message: errorResponse, to: remoteID, completionHandler: completionHandler)
            return
        }

        let handlerCompletionHandler: (Result<Void, Error>) -> Void = { [weak self] result in
            switch result {
            case .success:
                let remoteID = DHTRemoteNode.Identifier(
                    address: remoteAddress,
                    nodeID: nodeID
                )

                guard let self = self else {
                    completionHandler(result)
                    return
                }

                switch remoteID.address {
                case let .hostPort(host: host, port: _):
                    switch host {
                    case .ipv4:
                        if self.ipv4RoutingTable.containsNode(remoteID: remoteID) {
                            self.ipv4RoutingTable.updateQueryReceived(for: remoteID)
                            completionHandler(result)
                            return
                        }

                        if query.isReadOnlyNode {
                            completionHandler(result)
                        } else {
                            self.addToRoutingTable(nodeWithID: remoteID) { [weak self] _ in
                                guard let self = self else {
                                    completionHandler(result)
                                    return
                                }

                                self.ipv4RoutingTable.updateQueryReceived(for: remoteID)
                                completionHandler(result)
                            }
                        }
                    case .ipv6:
                        if self.ipv6RoutingTable.containsNode(remoteID: remoteID) {
                            self.ipv6RoutingTable.updateQueryReceived(for: remoteID)
                            completionHandler(result)
                            return
                        }

                        if query.isReadOnlyNode {
                            completionHandler(result)
                        } else {
                            self.addToRoutingTable(nodeWithID: remoteID) { [weak self] _ in
                                guard let self = self else {
                                    completionHandler(result)
                                    return
                                }

                                self.ipv6RoutingTable.updateQueryReceived(for: remoteID)
                                completionHandler(result)
                            }
                        }
                    case .name:
                        completionHandler(result)
                    }
                }

            case .failure:
                completionHandler(result)
            }
        }

        for remoteQueryMessageHandler in self.remoteQueryMessageHandlers {
            // TODO: Setup dictionary based on queryMethodName instead of looping
            if query.q == type(of: remoteQueryMessageHandler).queryMethodName {
                remoteQueryMessageHandler.handle(
                    query,
                    from: remoteAddress,
                    node: self,
                    completionHandler: handlerCompletionHandler
                )
                return
            }
        }

        let errorResponse = KRPCMessage(
            transactionID: query.t,
            errorCode: 204,
            errorMessage: "Method Unknown: \(query.q ?? "")",
            clientVersion: self.config.clientVersion
        )
        let remoteID = DHTRemoteNode.Identifier(address: remoteAddress, nodeID: query.queryingNodeID)
        self.send(message: errorResponse, to: remoteID, completionHandler: completionHandler)
    }

    /// Notifies the node it received an error.
    private func received(
        error: KRPCMessage,
        from remoteAddress: DHTNetworkAddress,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        assert(error.y == .error)
        guard let transactionID = error.transactionID else {
            // Not one of our original messages
            completionHandler(Result.success(()))
            return
        }

        if let transaction = self.transactions[Int(transactionID)] {
            guard transaction.remoteID.address == remoteAddress else {
                // Impersonator? Outdated info?
                completionHandler(Result.failure(DHTNodeError.receivedResponseFromUnknownAddress))
                return
            }

            self.completeTransaction(
                transactionID: transactionID,
                result: Result<KRPCMessage, Error>.failure(DHTResponseError.errorResponse(error))
            )
        }

        completionHandler(Result.success(()))
    }

    public func received(
        message: KRPCMessage,
        from remoteAddress: DHTNetworkAddress,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        switch message.y {
        case .error:
            self.received(error: message, from: remoteAddress, completionHandler: completionHandler)
        case .query:
            self.received(query: message, from: remoteAddress, completionHandler: completionHandler)
        case .response:
            self.received(response: message, from: remoteAddress, completionHandler: completionHandler)
        }
    }

    public func makeTransactionID() -> TransactionID {
        self.transactionIDCounter = self.transactionIDCounter &+ 1
        return self.transactionIDCounter
    }

    public func send(
        message: KRPCMessage,
        to remoteID: DHTRemoteNode.Identifier,
        queryTimeout: DispatchTimeInterval? = nil,
        queryCompletionHandler: ((Result<KRPCMessage, Error>) -> Void)? = nil,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let channel = self.channel else {
            queryCompletionHandler?(Result.failure(DHTNodeError.channelNotAvailable))
            completionHandler(Result.failure(DHTNodeError.channelNotAvailable))
            return
        }

        var message = message
        switch message.y {
        case .query:
            guard let transactionID = message.transactionID else {
                preconditionFailure("Transaction ID is not correctly set")
            }

            self.setupQuery(
                message: message,
                transactionID: Int(transactionID),
                to: remoteID,
                timeout: queryTimeout,
                completionHandler: queryCompletionHandler
            )
        case .error, .response:
            if let ip = remoteID.address.makeContactData(addressResolver: self.addressResolver) {
                message.ip = ip
            }
        }

        channel.send(message, to: remoteID.address) { [weak self] result in
            defer { completionHandler(result) }
            switch result {
            case .success:
                break
            case let .failure(error):
                guard let self = self else {
                    return
                }

                if message.y == .query {
                    guard let transactionID = message.transactionID else {
                        preconditionFailure("Expected transaction ID to exist")
                    }

                    self.completeTransaction(
                        transactionID: transactionID,
                        result: Result<KRPCMessage, Error>.failure(error)
                    )
                }
            }
        }
    }

    /// Setups a transaction for a query message to an address.
    private func setupQuery(
        message: KRPCMessage,
        transactionID: Int,
        to remoteID: DHTRemoteNode.Identifier,
        timeout: DispatchTimeInterval?,
        completionHandler: ((Result<KRPCMessage, Error>) -> Void)?
    ) {
        let transactionCompletionHandler: (Result<KRPCMessage, Error>) -> Void = { [weak self] result in
            switch result {
            case let .success(message):
                switch message.y {
                case .response:
                    guard !message.isReadOnlyNode else {
                        break
                    }
                    if remoteID.nodeID != nil {
                        self?.addToRoutingTable(nodeWithID: remoteID) { _ in
                            switch remoteID.address {
                            case let .hostPort(host: host, port: _):
                                switch host {
                                case .name:
                                    break
                                case .ipv4:
                                    self?.ipv4RoutingTable.updateResponseReceived(for: remoteID)
                                case .ipv6:
                                    self?.ipv6RoutingTable.updateResponseReceived(for: remoteID)
                                }
                            }
                        }
                    }
                case .error:
                    assertionFailure("Should not have encountered this code path")
                    switch remoteID.address {
                    case let .hostPort(host: host, port: _):
                        switch host {
                        case .name:
                            break
                        case .ipv4:
                            self?.ipv4RoutingTable.updateErrorReceived(for: remoteID)
                        case .ipv6:
                            self?.ipv6RoutingTable.updateErrorReceived(for: remoteID)
                        }
                    }
                case .query:
                    assertionFailure("Should not have encountered this code path")
                }
            case let .failure(error):
                switch error {
                case let responseError as DHTResponseError:
                    switch responseError {
                    case .errorResponse:
                        switch remoteID.address {
                        case let .hostPort(host: host, port: _):
                            switch host {
                            case .name:
                                break
                            case .ipv4:
                                self?.ipv4RoutingTable.updateErrorReceived(for: remoteID)
                            case .ipv6:
                                self?.ipv6RoutingTable.updateErrorReceived(for: remoteID)
                            }
                        }
                    case .timeout:
                        switch remoteID.address {
                        case let .hostPort(host: host, port: _):
                            switch host {
                            case .name:
                                break
                            case .ipv4:
                                self?.ipv4RoutingTable.updateResponseTimeout(for: remoteID)
                            case .ipv6:
                                self?.ipv6RoutingTable.updateResponseTimeout(for: remoteID)
                            }
                        }
                    case .cancelled:
                        break
                    }
                default:
                    break
                }
            }

            completionHandler?(result)
        }

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else {
                return
            }

            self.completeTransaction(
                transactionID: UInt16(transactionID),
                result: Result<KRPCMessage, Error>.failure(DHTResponseError.timeout)
            )
        }
        self.queue.asyncAfter(
            deadline: DispatchTime.now() + (timeout ?? self.config.queryTimeout),
            execute: timeoutWorkItem
        )

        let transaction = Transaction(
            id: transactionID,
            remoteID: remoteID,
            queryMessage: message,
            sent: DispatchTime.now(),
            completionHandler: transactionCompletionHandler,
            timeoutWorkItem: timeoutWorkItem
        )

        assert(self.transactions[transactionID] == nil)
        self.transactions[transactionID] = transaction

        self.transactionCreatedHandler?(transaction)
    }
}

extension DHT: CustomDebugStringConvertible {
    public var debugDescription: String {
        // swiftlint:disable line_length
        return "DHT(config: \(config), transactions: \(transactions.compactMap { $0 }), ipv4RoutingTable: \(ipv4RoutingTable), ipv6RoutingTable: \(ipv6RoutingTable), secretTokens: \(secretTokens))"
        // swiftlint:enable line_length
    }
}
