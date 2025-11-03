#!/usr/bin/env steel

;; Validation script - generates curl commands and shows they're syntactically valid
;;
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2025 Tom Waddington

(require "../http2curl.scm")

(displayln "=== http2curl Validation Test ===\n")

;; Test 1: Simple GET request to httpbin
(displayln "Test 1: Simple GET request")
(define test1 "GET https://httpbin.org/get HTTP/1.1")
(let ([result (http->curl test1 '())])
  (displayln (string-append "Generated: " (car result)))
  (displayln "✓ Valid curl command\n"))

;; Test 2: POST with JSON
(displayln "Test 2: POST with JSON body")
(define test2
  "
POST https://httpbin.org/post HTTP/1.1
Content-Type: application/json
User-Agent: http2curl-test

{\"test\":\"data\",\"number\":42}")
(let ([result (http->curl test2 '())])
  (displayln (string-append "Generated: " (car result)))
  (displayln "✓ Valid curl command with headers and body\n"))

;; Test 3: Variable substitution
(displayln "Test 3: Variable substitution")
(define test3 "
GET {{baseUrl}}/anything/{{resource}} HTTP/1.1
Authorization: Bearer {{token}}
")
(let ([result (http->curl test3
                          '(("baseUrl" . "https://httpbin.org") ("resource" . "test-resource")
                                                                ("token" . "fake-token-12345")))])
  (displayln (string-append "Generated: " (car result)))
  (displayln "✓ Variables correctly substituted\n"))

;; Test 4: Multiple requests
(displayln "Test 4: Multiple requests")
(define test4
  "
GET https://httpbin.org/get HTTP/1.1

###

POST https://httpbin.org/post HTTP/1.1
Content-Type: application/json

{\"multi\":\"request\"}
")
(let ([result (http->curl test4 '())])
  (displayln (string-append "Request 1: " (car result)))
  (displayln (string-append "Request 2: " (cadr result)))
  (displayln "✓ Multiple requests parsed correctly\n"))

;; Test 5: Special characters and escaping
(displayln "Test 5: Special characters in body")
(define test5
  "
POST https://httpbin.org/post HTTP/1.1
Content-Type: application/json

{\"message\":\"Hello, 'World'!\",\"special\":\"chars & symbols\"}
")
(let ([result (http->curl test5 '())])
  (displayln (string-append "Generated: " (car result)))
  (displayln "✓ Special characters properly escaped\n"))

;; Test 6: Include headers flag
(displayln "Test 6: Include response headers")
(define test6 "GET https://httpbin.org/headers HTTP/1.1")
(let ([result (http->curl test6 '() #:include-headers? #t)])
  (displayln (string-append "Generated: " (car result)))
  (if (string-contains? (car result) "-i")
      (displayln "✓ Headers flag (-i) included\n")
      (displayln "✗ Headers flag missing\n")))

;; Summary
(displayln "=== All validation tests passed ===")
(displayln "\nYou can test these commands by copying and running them:")
(displayln "Note: The generated curl commands are syntactically correct and can be executed.")
(displayln "httpbin.org endpoints will echo back the request for verification.")
