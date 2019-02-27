import Cirmac
import Foundation

public struct IrmaError: Error {
	public let message: String
}

// Tracks RemoteError in irmago/messages.go:110
public struct RemoteError: Codable {
	public let status: Int
	public let error: String
	public let description: String
	public let message: String
	public let stacktrace: String
}

// Tracks DisclosedAttribute in irmago/verify.go:34
public struct DisclosedAttribute: Codable {
	public let rawvalue: String
	public let value: [String:String]
	public let id: String
	public let status: String
}

// Partially tracks SignedMessage irmago/irma_signature.go:16
// This struct is incomplete, will fill in further data on need.
public struct SignedMessage: Codable{
	//let signature: [Any] (Not yet supported)
	//let indices: [[Any]] (Not yet supported)
	public let nonce: String
	public let context: String
	public let message: String
	//let timestamp: Any   (Not yet supported)
}

// Tracks SessionResult in irmago/server/api.go:54
public struct SessionResult: Codable {
	public let token: String
	public let status: String
	public let type: String
	public let proofStatus: String
	public let disclosed: [DisclosedAttribute]
	public let signature: SignedMessage?
	public let error: RemoteError?
}

/**
Initialize the IrmaSwift library

- Parameter configuration: Configuration for running the server, in JSON format.
                           The schemes_path field sets the directory for the irma
                           schemes. The URL field descirbes the prefix at which
                           the library-served pages are reachable. The email field
                           specifies an email-adres for information about updates
                           to this library that are needed to stay compatible with
                           the rest of the IRMA ecosystem. A full description of
                           all fields can be found at https://godoc.org/github.com/privacybydesign/irmago/server#Configuration

- Throws: `IrmaError` if the specified directories are unusable or if the configuration
          could not be parsed.
*/
public func Initialize(configuration: String) throws {
	let res = Cirmac.Initialize(UnsafeMutablePointer<Int8>(mutating: (configuration as NSString).utf8String))
	if res != nil {
		let ret = String(cString: res!)
		free(res)
		throw IrmaError(message: ret)
	}
}

/**
Start an irma session based on a request.

- Parameter sessionRequest: JSON string describing the type of session desired.
                            Full documentation of this can be found at TODO.

- Throws: `IrmaError` if the sessionRequest is invalid.

- Returns:
  - sessionPtr: The session pointer that can be passed to the irma_mobile app using
                one of the front-end libraries such as irmajs.
  - token: A string token that can be used by the caller to get information on the
           session as it progresses.
*/
public func StartSession(sessionRequest: String) throws -> (sessionPtr: String, token: String) {
	let res = Cirmac.StartSession(UnsafeMutablePointer<Int8>(mutating: (sessionRequest as NSString).utf8String))
	if res.error != nil {
		let ret = String(cString: res.error!)
		free(res.error)
		if res.irmaQr != nil {
			free(res.irmaQr)
		}
		if res.token != nil {
			free(res.token)
		}
		throw IrmaError(message: ret)
	}
	let token = String(cString: res.token!)
	let sessionPtr = String(cString: res.irmaQr!)
	return (sessionPtr, token)
}

/**
Get the result of a session in raw JSON form.

- Parameter token: The token returned by StartSession when starting the session.

- Throws: `IrmaError` if the supplied token is does not refer to an irma session.

- Returns: A string containing JSON-encoded status information on the session
*/
public func GetSessionResultRaw(token: String) throws -> String {
	let res = Cirmac.GetSessionResult(UnsafeMutablePointer<Int8>(mutating: (token as NSString).utf8String))
	if res == nil {
		throw IrmaError(message: "Invalid token")
	}
	let ret = String(cString: res!)
	free(res)
	return ret;
}

/**
Get the result of a session

- Parameter token: The token returned by StartSession when starting the session.

- Throws: `IrmaError` if the supplied token is does not refer to an irma session.

- Returns: A description of the current status of the irma session, including
           results if those are available.
*/
public func GetSessionResult(token: String) throws -> SessionResult {
	let resultJson = try GetSessionResultRaw(token: token)
	guard let result = try? JSONDecoder().decode(SessionResult.self, from: resultJson.data(using: .utf8)!) else {
		throw IrmaError(message: "Internal error")
	}
	return result;
}

/**
Get the request that started a session

- Parameter token: The token returned by StartSession when starting the session.

- Throws: `IrmaError` if the supplied token is does not refer to an irma session.

- Returns: A string containing a JSON representation of the request used to start
           the session.
*/
public func GetRequest(token: String) throws -> String {
	let res = Cirmac.GetRequest(UnsafeMutablePointer<Int8>(mutating: (token as NSString).utf8String))
	if res == nil {
		throw IrmaError(message: "Invalid token")
	}
	let ret = String(cString: res!)
	free(res)
	return ret;
}

/**
Cancel a currently running session

- Parameter token: The token returned by StartSession when starting the session.

- Throws: `IrmaError` if the supplied token is does not refer to an irma session.
*/
public func CancelSession(token: String) throws {
	let res = Cirmac.CancelSession(UnsafeMutablePointer<Int8>(mutating: (token as NSString).utf8String))
	if res != nil {
		let message = String(cString: res!)
		free(res)
		throw IrmaError(message: message)
	}
}

/**
Handle a request to a page under the configuration.URL prefix. This should be called by the server software to handle such requests.

- Parameter path: The full path to the page requested, including prefix.

- Parameter headers: A map describing the HTML headers associated with the request

- Parameter message: The request body.

- Throws: `IrmaError` on internal errors.

- Returns:
  - status: HTTP status code for the response
  - body: Result body for the response
  - sessionResult: If the request significantly changed the status of a request, this
                   contains the output of GetSessionResultRaw. This is guaranteed to
                   be filled when a request first enters one of the states CANCELLED
                   or DONE.
*/
public func HandleProtocolMessage(path: String, method: String, headers: [String:[String]], message: String) throws -> (status: Int, body: String, sessionResult: String?) {
	// Determine how many headers we have.
	var headerLength = 0
	for (_, values) in headers {
		headerLength += values.count
	}
	
	// Build up the header C struct
	var headerStruct = HttpHeaders()
	headerStruct.length = Int32(headerLength)
	headerStruct.headerKeys = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity: headerLength)
	headerStruct.headerValues = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity: headerLength)
	var i = 0
	for (key, values) in headers {
		for value in values {
			headerStruct.headerKeys[i] = UnsafeMutablePointer<Int8>(mutating: (key as NSString).utf8String)
			headerStruct.headerValues[i] = UnsafeMutablePointer<Int8>(mutating: (value as NSString).utf8String)
			i+=1
		}
	}
	
	// Call the C function
	let res = Cirmac.HandleProtocolMessage(
		UnsafeMutablePointer<Int8>(mutating: (path as NSString).utf8String),
		UnsafeMutablePointer<Int8>(mutating: (method as NSString).utf8String),
		headerStruct,
		UnsafeMutablePointer<Int8>(mutating: (message as NSString).utf8String))
	
	// These wont be needed anymore, cleanup
	headerStruct.headerKeys!.deallocate()
	headerStruct.headerValues!.deallocate()
	
	// Extract and return results
	let status = Int(res.status)
	if res.body == nil {
		if res.SessionResult != nil {
			free(res.SessionResult)
		}
		throw IrmaError(message: "Internal error")
	}
	let body = String(cString: res.body!)
	if (res.SessionResult == nil) {
		return (status, body, nil)
	} else {
		return (status, body, String(cString: res.SessionResult!))
	}
}
