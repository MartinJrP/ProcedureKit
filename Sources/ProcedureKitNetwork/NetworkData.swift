//
//  ProcedureKit
//
//  Copyright © 2015-2018 ProcedureKit. All rights reserved.
//

#if SWIFT_PACKAGE
    import ProcedureKit
    import Foundation
#endif

/**
 NetworkDataProcedure is a simple procedure which will perform a data task using
 URLSession based APIs. It only supports the completion block style API, therefore
 do not use this procedure if you wish to use delegate based APIs on URLSession.
*/
open class NetworkDataProcedure: Procedure, InputProcedure, OutputProcedure, NetworkOperation {

    public typealias NetworkResult = ProcedureResult<HTTPPayloadResponse<Data>>
    public typealias CompletionBlock = (NetworkResult) -> Void

    public var input: Pending<URLRequest> {
        get { return stateLock.withCriticalScope { _input } }
        set {
            stateLock.withCriticalScope {
                _input = newValue
            }
        }
    }

    public var output: Pending<NetworkResult> {
        get { return stateLock.withCriticalScope { _output } }
        set {
            stateLock.withCriticalScope {
                _output = newValue
            }
        }
    }

    public let session: NetworkSession
    public let completion: CompletionBlock

    private let stateLock = NSLock()
    internal private(set) var task: NetworkDataTask? // internal for testing
    private var _input: Pending<URLRequest> = .pending
    private var _output: Pending<NetworkResult> = .pending

    public init(session: NetworkSession, request: URLRequest? = nil, completionHandler: @escaping CompletionBlock = { _ in }) {

        self.session = session
        self.completion = completionHandler
        super.init()
        self.input = request.flatMap { .ready($0) } ?? .pending

        addDidCancelBlockObserver { procedure, _ in
            procedure.task?.cancel()
            // a call to `finish()` is not necessary here, because the URLSessionTask's
            // completion handler is always called (even if cancelled) and it
            // ensures that `finish()` is called
        }
    }

    open override func execute() {
        guard let request = input.value else {
            finish(withResult: .failure(ProcedureKitError.requirementNotSatisfied()))
            return
        }

        guard !isCancelled else {
            finish()
            return
        }
        task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let strongSelf = self else { return }

            if let error = error {
                if strongSelf.isCancelled, let error = error as? URLError, error.code == .cancelled {
                    // special case: hide the task's cancellation error
                    // if the NetworkProcedure was cancelled
                    strongSelf.finish()
                    return
                }
                strongSelf.finish(withResult: .failure(error))
                return
            }

            guard let data = data, let response = response as? HTTPURLResponse else {
                strongSelf.finish(withResult: .failure(ProcedureKitError.unknown))
                return
            }

            let http = HTTPPayloadResponse(payload: data, response: response)

            strongSelf.completion(.success(http))
            strongSelf.finish(withResult: .success(http))
        }

        log.notice(message: "Will make request: \(request)")
        task?.resume()
    }
}
