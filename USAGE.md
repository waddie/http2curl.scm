# http2curl Usage Guide

## Overview

`http2curl.scm` is a Steel Scheme library that translates http format requests into curl commands.

## Installation

Simply copy `http2curl.scm` to your project directory or include it in your Steel load path.

## Basic Usage

```scheme
(require "http2curl.scm")

;; Simple GET request
(http->curl "GET https://api.example.com/users HTTP/1.1" '())
;; => ("curl https://api.example.com/users")

;; POST with headers and JSON body
(http->curl
  "POST https://api.example.com/users HTTP/1.1
Content-Type: application/json
Authorization: Bearer token123

{\"name\":\"John\",\"email\":\"john@example.com\"}"
  '())
;; => ("curl -X POST -H \"Content-Type: application/json\" -H \"Authorization: Bearer token123\" --data-raw '{\"name\":\"John\",\"email\":\"john@example.com\"}' https://api.example.com/users")
```

## Function Signature

```scheme
(http->curl http-input variables #:include-headers? bool) -> (listof string?)
```

### Parameters

- **http-input**: Either a string or a list of strings containing http format requests
  - **String**: Single string with one or more http requests
  - **List**: Multiple strings (e.g., from Helix multi-selections), each containing one or more requests
- **variables**: Association list of variable substitutions, e.g., `'(("token" . "abc123") ("baseUrl" . "https://api.example.com"))`
- **#:include-headers?**: Optional keyword argument (default: `#f`). When `#t`, adds the `-i` flag to include response headers in curl output

### Return Value

Returns a flat list of curl command strings from all inputs. When given a list of strings, requests from all strings are processed and combined into a single list.

## Variable Substitution

Variables in the http format are referenced with `{{varName}}` syntax. Pass the values as an association list:

```scheme
(define http-request "
GET {{baseUrl}}/api/users HTTP/1.1
Authorization: Bearer {{token}}
")

(define vars '(("baseUrl" . "https://example.com")
               ("token" . "abc123xyz")))

(http->curl http-request vars)
;; => ("curl -H \"Authorization: Bearer abc123xyz\" https://example.com/api/users")
```

## Multiple Requests

### Using ### Separators

Separate multiple requests with `###` within a single string:

```scheme
(define multi-request "
GET https://api.example.com/users HTTP/1.1

###

POST https://api.example.com/users HTTP/1.1
Content-Type: application/json

{\"name\":\"Jane\"}")

(http->curl multi-request '())
;; => ("curl https://api.example.com/users"
;;     "curl -X POST -H \"Content-Type: application/json\" --data-raw '{\"name\":\"Jane\"}' https://api.example.com/users")
```

### Multi-Selection (Helix Editor)

Pass a list of strings for multi-selection scenarios. This is perfect for Helix's multi-selection model:

```scheme
;; User made 3 selections in Helix, each containing a complete request
(define selections
  '("GET https://api.example.com/users/{{userId}} HTTP/1.1
Authorization: Bearer {{token}}"

    "PUT https://api.example.com/users/{{userId}} HTTP/1.1
Content-Type: application/json

{\"name\":\"{{userName}}\"}"

    "DELETE https://api.example.com/sessions/{{sessionId}} HTTP/1.1
Authorization: Bearer {{token}}"))

(define vars '(("userId" . "12345")
               ("token" . "abc123")
               ("userName" . "John")
               ("sessionId" . "sess-xyz")))

(http->curl selections vars)
;; => ("curl -H \"Authorization: Bearer abc123\" https://api.example.com/users/12345"
;;     "curl -X PUT -H \"Content-Type: application/json\" --data-raw '{\"name\":\"John\"}' https://api.example.com/users/12345"
;;     "curl -X DELETE -H \"Authorization: Bearer abc123\" https://api.example.com/sessions/sess-xyz")
```

Each selection can also contain multiple requests with `###` separators, and all will be processed into a single flat list.

## Including Response Headers

Use the `#:include-headers?` parameter to add the `-i` flag:

```scheme
(http->curl "GET https://api.example.com/status HTTP/1.1" '() #:include-headers? #t)
;; => ("curl -i https://api.example.com/status")
```

## External File References

Reference external files for request bodies using `< filepath`:

```scheme
(http->curl "
POST https://api.example.com/upload HTTP/1.1
Content-Type: application/json

< data.json" '())
;; => ("curl -X POST -H \"Content-Type: application/json\" -d @data.json https://api.example.com/upload")
```

## Complete Example

```scheme
#!/usr/bin/env steel

(require "http2curl.scm")

(define api-request "
###
# Fetch access token
GET {{baseUrl}}/api/v1/token HTTP/1.1
Accept: application/json
Authorization: Basic {{credentials}}

###
# Create new user
POST {{baseUrl}}/api/v1/users HTTP/1.1
Accept: application/json
Content-Type: application/json
Authorization: Bearer {{token}}

{
  \"name\": \"{{userName}}\",
  \"email\": \"{{userEmail}}\"
}
")

(define config '(("baseUrl" . "https://api.example.com")
                 ("credentials" . "dXNlcjpwYXNz")
                 ("token" . "eyJhbGc...")
                 ("userName" . "John Doe")
                 ("userEmail" . "john@example.com")))

;; Generate curl commands with response headers
(let ((commands (http->curl api-request config #:include-headers? #t)))
  (displayln "Generated curl commands:")
  (for-each (lambda (cmd)
              (displayln cmd)
              (displayln ""))
            commands))
```

## Supported Features

- HTTP methods (GET, POST, PUT, DELETE, PATCH, etc.)
- Headers
- Request bodies (JSON, plain text, multiline)
- Variable substitution with `{{varName}}`
- Multiple requests per file (separated by `###`)
- External file references (`< filepath`)
- Include response headers option (`-i` flag)
- Proper shell escaping for special characters

## Notes

- Empty requests (no URL) are automatically filtered out
- HTTP version (e.g., `HTTP/1.1`) is optional and ignored
- Comments starting with `#` or `//` are skipped
- The library does not execute curl commands, only generates them
- Variable definitions (`@varName = value`) in http files are NOT parsed; variables must be passed as the second parameter
