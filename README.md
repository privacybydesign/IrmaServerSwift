# IrmaServerSwift

A package for building servers using IRMA in swift.

## Build instructions

This package requires a version of the `irmac` library to be present. Prebuilt libraries for Mac and Linux can be downloaded from the releases tab. During building of projects based on this library, one needs to tell the swift package manager where to find these using `-Xlinker -L/path/to/irmac/library/`

## Usage

This library allows integration of an irma server into the rest of your web server written in Swift. Before use, it needs to be initialized:
```swift
Initialize(configuration: "{
	\"url\": \"https://localhost:8080/irma/\"
}")
```
This is the `url` that the IRMA app will connect to during IRMA sessions (so ensure that it is reachable by IRMA apps).

After initialization, the server will need to call the library to handle every request for an url starting with prefix above. The library will then return information for the http response. As an example, this can be implemented in a kitura server as follows:
```swift
router.all("/irma/*") { request, response, next in
	// Connect /irma to the IRMA server library

	// Capture body (note that the unwrapping of ? is doubled, due to also capturing any errors here that way)
	let Mbody = try? request.readString()
	let body : String = (Mbody ?? "") ?? ""

	// Extract and convert headers to a simple map
	var headerMap : [String:[String]] = [:]
	for (key, value) in request.headers {
		if value != nil {
			if headerMap[key] == nil {
				headerMap[key] = []
			}
			headerMap[key]!.append(value!)
		}
	}

	// Let the IRMA server library handle the actual request
	let Mres = try? HandleProtocolMessage(path: request.originalURL, method: request.method.rawValue, headers: headerMap, message: body)

	// Deal with errors
	guard let res = Mres else {
		response.send(status: .internalServerError)
		next()
		return
	}

	// And output the result
	guard let statuscode = HTTPStatusCode(rawValue: res.status) else {
		// There might be a mismatch in status code requested by the library and those available by kitura
		// This should never happen, and hopefully kitura will get a better mechanism for this in the future
		response.send(status: .internalServerError)
		next()
		return
	}
	response.status(statuscode)
	response.send(res.body)
	next()
}
```

To start an IRMA session, the server can now call `StartSession` with a session request as described in TODO. This results in a token and a session pointer. The session pointer can be passed to `irma_mobile` using one of the front-end libraries such as `irmajs`. The token allows the requestor to monitor the sessions status and fetch its results. The results of the session can be obtained using `GetSessionResult`, which returns the status of the library. A example of how to use this, taken from the example server, is shown below:

```swift
router.get("/startSession") { request, response, next in
	// Start the session
	guard let (sessionptr, token) = try? StartSession(
		sessionRequest:"{
			\"type\": \"disclosing\",
			\"content\": [{
				\"label\": \"Naam\", \"attributes\": [
					\"irma-demo.MijnOverheid.fullName.firstname\"
				]
			}]
		}") else {
		// Deal with problems (somewhat) gracefully
		response.send(status: .internalServerError)
		next()
		return
	}
	// And send the resulting session ptr and token to client
	let result = ["sessionptr": sessionptr, "token": token]
	response.send(json: result)
	next()
}
router.get("/fetch") { request, response, next in
	// See if the request actually has the data we need
	guard let token = request.urlURL.query else {
		response.send(status: .badRequest)
		next()
		return
	}
	// Fetch results (if available)
	guard let sesResult = try? GetSessionResult(token: token) else {
		response.send(status: .notFound)
		next()
		return
	}
	// Check if the session is actually in a useful state
	if (sesResult.status != "DONE") {
		response.send(status: .notFound)
		next()
		return
	}
	// And disclose the first revealed attribute (this will be irma-demo.MijnOverheid.fullName.firstname, given our request)
	response.send(sesResult.disclosed[0].rawvalue)
	next()
}
```

## Email

Users are encouraged to provide an email address with the `email` option in the `configuration` json, subscribing for notifications about changes in the IRMA software or ecosystem. [More information](https://github.com/privacybydesign/irmago/tree/master/server).

## Example server

An example server build using this library can be found in the [irma-examples](https://github.com/privacybydesign/irma-examples/tree/master/demoserverswift).

