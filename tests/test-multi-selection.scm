#!/usr/bin/env steel

;; Test file for multi-selection (list input) functionality
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
  (displayln "Input type:")
  (displayln (if (string? input) "  Single string" "  List of strings"))
  (when (list? input)
    (displayln (string-append "  Number of selections: " (int->string (length input))))
    (displayln "  Selections:"))
  (if (list? input)
      (for-each
       (lambda (s)
         (displayln (string-append "    - " (substring s 0 (min 50 (string-length s))) "...")))
       input)
      (displayln (string-append "  " (substring input 0 (min 50 (string-length input))) "...")))

  (displayln "\nVariables:")
  (displayln variables)
  (displayln (string-append "\nInclude headers: " (if include-headers? "true" "false")))
  (displayln "\nResult:")
  (let ([result (http->curl input variables #:include-headers? include-headers?)])
    (for-each (lambda (cmd) (displayln (string-append "  " cmd))) result)
    (displayln "\nExpected:")
    (for-each (lambda (cmd) (displayln (string-append "  " cmd))) expected)
    (displayln "---")))

;; Test 1: List with single selection (should behave like string input)
(test-case "List with single selection"
  '("GET https://api.example.com/users HTTP/1.1")
  '()
  '("curl https://api.example.com/users")
  #f)

;; Test 2: List with multiple separate GET requests
(test-case "Multiple selections - separate GET requests"
  '("GET https://api.example.com/users HTTP/1.1" "GET https://api.example.com/posts HTTP/1.1"
                                                 "GET https://api.example.com/comments HTTP/1.1")
  '()
  '("curl https://api.example.com/users" "curl https://api.example.com/posts"
                                         "curl https://api.example.com/comments")
  #f)

;; Test 3: List with mixed request types and headers
(test-case "Multiple selections - mixed requests with headers"
  '("GET https://api.example.com/users HTTP/1.1\nAuthorization: Bearer token1"
    "POST https://api.example.com/posts HTTP/1.1\nContent-Type: application/json\n\n{\"title\":\"Post 1\"}")
  '()
  '("curl -H \"Authorization: Bearer token1\" https://api.example.com/users"
    "curl -X POST -H \"Content-Type: application/json\" --data-raw '{\"title\":\"Post 1\"}' https://api.example.com/posts")
  #f)

;; Test 4: List where each selection has multiple requests (### separated)
(test-case "Multiple selections with ### separators"
  '("GET https://api.example.com/users HTTP/1.1\n\n###\n\nPOST https://api.example.com/users HTTP/1.1\nContent-Type: application/json\n\n{\"name\":\"Alice\"}"
    "GET https://api.example.com/posts HTTP/1.1\n\n###\n\nDELETE https://api.example.com/posts/123 HTTP/1.1")
  '()
  '("curl https://api.example.com/users"
    "curl -X POST -H \"Content-Type: application/json\" --data-raw '{\"name\":\"Alice\"}' https://api.example.com/users"
    "curl https://api.example.com/posts"
    "curl -X DELETE https://api.example.com/posts/123")
  #f)

;; Test 5: List with variable substitution
(test-case "Multiple selections with variable substitution"
  '("GET {{baseUrl}}/api/v1/users HTTP/1.1\nAuthorization: Bearer {{token}}"
    "GET {{baseUrl}}/api/v1/posts HTTP/1.1\nAuthorization: Bearer {{token}}"
    "GET {{baseUrl}}/api/v1/comments HTTP/1.1\nAuthorization: Bearer {{token}}")
  '(("baseUrl" . "https://example.com") ("token" . "abc123"))
  '("curl -H \"Authorization: Bearer abc123\" https://example.com/api/v1/users"
    "curl -H \"Authorization: Bearer abc123\" https://example.com/api/v1/posts"
    "curl -H \"Authorization: Bearer abc123\" https://example.com/api/v1/comments")
  #f)

;; Test 6: List with include-headers flag
(test-case "Multiple selections with include-headers"
  '("GET https://api.example.com/status HTTP/1.1" "GET https://api.example.com/health HTTP/1.1")
  '()
  '("curl -i https://api.example.com/status" "curl -i https://api.example.com/health")
  #t)

;; Test 7: Mixed - some selections with empty requests
(test-case "Multiple selections with some empty"
  '("GET https://api.example.com/users HTTP/1.1" "" "GET https://api.example.com/posts HTTP/1.1")
  '()
  '("curl https://api.example.com/users" "curl https://api.example.com/posts")
  #f)

;; Test 8: Realistic Helix multi-selection scenario
(displayln "\n\n=== Realistic Helix Multi-Selection Scenario ===")
(displayln "Scenario: User selected 3 different API endpoints in an .http file")
(displayln "Each selection is a complete request block\n")

(define helix-selections
  '("###
# Get user profile
GET {{baseUrl}}/api/v1/users/{{userId}} HTTP/1.1
Accept: application/json
Authorization: Bearer {{token}}"
    "###
# Update user
PUT {{baseUrl}}/api/v1/users/{{userId}} HTTP/1.1
Content-Type: application/json
Authorization: Bearer {{token}}

{
  \"name\": \"{{userName}}\",
  \"email\": \"{{userEmail}}\"
}"
    "###
# Delete user session
DELETE {{baseUrl}}/api/v1/sessions/{{sessionId}} HTTP/1.1
Authorization: Bearer {{token}}"))

(define helix-vars
  '(("baseUrl" . "https://api.example.com") ("userId" . "12345")
                                            ("token" . "eyJhbGc...")
                                            ("userName" . "John Doe")
                                            ("userEmail" . "john@example.com")
                                            ("sessionId" . "sess-abc-123")))

(displayln "Input: 3 selections from Helix editor")
(for-each
 (lambda (sel)
   (displayln (string-append "\nSelection:\n" (substring sel 0 (min 100 (string-length sel))) "...")))
 helix-selections)

(displayln "\n\nGenerated curl commands:")
(let ([commands (http->curl helix-selections helix-vars #:include-headers? #t)])
  (for-each (lambda (cmd)
              (displayln "")
              (displayln cmd))
            commands))

(displayln "\n\n=== All multi-selection tests completed ===")
