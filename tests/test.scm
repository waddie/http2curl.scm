#!/usr/bin/env steel

;; Test file for http2curl.scm
;;
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2025 Tom Waddington

(require "../http2curl.scm")

(define (test-case name
          input
          variables
          expected
          include-headers?)
  (displayln (string-append "\n=== Test: " name " ==="))
  (let ([result (http->curl input variables #:include-headers? include-headers?)])
    (displayln "Input:")
    (displayln input)
    (displayln "\nVariables:")
    (displayln variables)
    (displayln (string-append "\nInclude headers: " (if include-headers? "true" "false")))
    (displayln "\nResult:")
    (for-each (lambda (cmd) (displayln cmd)) result)
    (displayln "\nExpected:")
    (for-each (lambda (cmd) (displayln cmd)) expected)
    (displayln "---")))

;; Test 1: Simple GET request
(test-case "Simple GET"
  "GET https://api.example.com/users HTTP/1.1"
  '()
  '("curl https://api.example.com/users")
  #f)

;; Test 2: POST with headers and JSON body
(test-case "POST with JSON"
  "POST https://api.example.com/users HTTP/1.1\nContent-Type: application/json\nAuthorization: Bearer token123\n\n{\"name\":\"John\",\"email\":\"john@example.com\"}"
  '()
  '("curl -X POST -H \"Content-Type: application/json\" -H \"Authorization: Bearer token123\" --data-raw '{\"name\":\"John\",\"email\":\"john@example.com\"}' https://api.example.com/users")
  #f)

;; Test 3: GET with include-headers flag
(test-case "GET with headers included"
  "GET https://api.example.com/status HTTP/1.1"
  '()
  '("curl -i https://api.example.com/status")
  #t)

;; Test 4: Variable substitution
(test-case "Variable substitution"
  "POST {{baseUrl}}/api/users HTTP/1.1\nAuthorization: Bearer {{token}}\nContent-Type: application/json\n\n{\"id\":\"{{userId}}\"}"
  '(("baseUrl" . "https://example.com") ("token" . "abc123") ("userId" . "42"))
  '("curl -X POST -H \"Authorization: Bearer abc123\" -H \"Content-Type: application/json\" --data-raw '{\"id\":\"42\"}' https://example.com/api/users")
  #f)

;; Test 5: Multiple requests
(test-case "Multiple requests"
  "GET https://api.example.com/users HTTP/1.1\n\n###\n\nPOST https://api.example.com/users HTTP/1.1\nContent-Type: application/json\n\n{\"name\":\"Jane\"}"
  '()
  '("curl https://api.example.com/users"
    "curl -X POST -H \"Content-Type: application/json\" --data-raw '{\"name\":\"Jane\"}' https://api.example.com/users")
  #f)

;; Test 6: External file reference
(test-case "External file body"
  "POST https://api.example.com/upload HTTP/1.1\nContent-Type: application/json\n\n< data.json"
  '()
  '("curl -X POST -H \"Content-Type: application/json\" -d @data.json https://api.example.com/upload")
  #f)

;; Test 7: Request without body
(test-case "DELETE without body"
  "DELETE https://api.example.com/users/123 HTTP/1.1\nAuthorization: Bearer token"
  '()
  '("curl -X DELETE -H \"Authorization: Bearer token\" https://api.example.com/users/123")
  #f)

(displayln "\n=== All tests completed ===")
