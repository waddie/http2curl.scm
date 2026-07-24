;; SPDX-License-Identifier: MIT
;; Copyright (c) 2025, 2026 Tom Waddington

;;; test-multi-selection.scm - list input, as produced by Helix
;;; multi-selections. Results from every selection land in one flat list.
;;;
;;; Run from the repo root: steel tests/test-multi-selection.scm

(require "steel-test/test.scm")
(require "../http2curl.scm")

(deftest list-input
  (testing "a single-element list matches the string form"
    (is (= (http->curl "GET https://api.example.com/users HTTP/1.1" '())
         (http->curl '("GET https://api.example.com/users HTTP/1.1") '()))))
  (testing "one command per selection, in order"
    (is (= '("curl 'https://api.example.com/users'"
             "curl 'https://api.example.com/posts'"
             "curl 'https://api.example.com/comments'")
         (http->curl '("GET https://api.example.com/users HTTP/1.1"
                       "GET https://api.example.com/posts HTTP/1.1"
                       "GET https://api.example.com/comments HTTP/1.1")
           '()))))
  (testing "selections may differ in method, headers and body"
    (is (= '("curl -H 'Authorization: Bearer token1' 'https://api.example.com/users'"
             "curl -X POST -H 'Content-Type: application/json' --data-raw '{\"title\":\"Post 1\"}' 'https://api.example.com/posts'")
         (http->curl
           '("GET https://api.example.com/users HTTP/1.1\nAuthorization: Bearer token1"
             "POST https://api.example.com/posts HTTP/1.1\nContent-Type: application/json\n\n{\"title\":\"Post 1\"}")
           '()))))
  (testing "empty selections are dropped"
    (is (= '("curl 'https://api.example.com/users'" "curl 'https://api.example.com/posts'")
         (http->curl '("GET https://api.example.com/users HTTP/1.1"
                       ""
                       "GET https://api.example.com/posts HTTP/1.1")
           '())))))

(deftest flattening
  (testing "a selection holding ### separators contributes every request"
    (is (= '("curl 'https://api.example.com/users'"
             "curl -X POST -H 'Content-Type: application/json' --data-raw '{\"name\":\"Alice\"}' 'https://api.example.com/users'"
             "curl 'https://api.example.com/posts'"
             "curl -X DELETE 'https://api.example.com/posts/123'")
         (http->curl
           '("GET https://api.example.com/users HTTP/1.1\n\n###\n\nPOST https://api.example.com/users HTTP/1.1\nContent-Type: application/json\n\n{\"name\":\"Alice\"}"
             "GET https://api.example.com/posts HTTP/1.1\n\n###\n\nDELETE https://api.example.com/posts/123 HTTP/1.1")
           '())))))

(deftest shared-options
  (testing "one variable map serves every selection"
    (is (= '("curl -H 'Authorization: Bearer abc123' 'https://example.com/api/v1/users'"
             "curl -H 'Authorization: Bearer abc123' 'https://example.com/api/v1/posts'")
         (http->curl '("GET {{baseUrl}}/api/v1/users HTTP/1.1\nAuthorization: Bearer {{token}}"
                       "GET {{baseUrl}}/api/v1/posts HTTP/1.1\nAuthorization: Bearer {{token}}")
           '(("baseUrl" . "https://example.com") ("token" . "abc123"))))))
  (testing "include-headers applies to every selection"
    (is (= '("curl -i 'https://api.example.com/status'" "curl -i 'https://api.example.com/health'")
         (http->curl '("GET https://api.example.com/status HTTP/1.1"
                       "GET https://api.example.com/health HTTP/1.1")
           '()
           #:include-headers?
           #t)))))

;; Three request blocks selected in an .http file, each with its own leading
;; separator and comment line.
(deftest helix-selection-blocks
  (testing "comments and separators inside selections"
    (is (= '("curl -i -H 'Accept: application/json' -H 'Authorization: Bearer eyJhbGc...' 'https://api.example.com/api/v1/users/12345'"
             "curl -X PUT -i -H 'Content-Type: application/json' -H 'Authorization: Bearer eyJhbGc...' --data-raw '{\n  \"name\": \"John Doe\",\n  \"email\": \"john@example.com\"\n}' 'https://api.example.com/api/v1/users/12345'"
             "curl -X DELETE -i -H 'Authorization: Bearer eyJhbGc...' 'https://api.example.com/api/v1/sessions/sess-abc-123'")
         (http->curl
           '("###\n# Get user profile\nGET {{baseUrl}}/api/v1/users/{{userId}} HTTP/1.1\nAccept: application/json\nAuthorization: Bearer {{token}}"
             "###\n# Update user\nPUT {{baseUrl}}/api/v1/users/{{userId}} HTTP/1.1\nContent-Type: application/json\nAuthorization: Bearer {{token}}\n\n{\n  \"name\": \"{{userName}}\",\n  \"email\": \"{{userEmail}}\"\n}"
             "###\n# Delete user session\nDELETE {{baseUrl}}/api/v1/sessions/{{sessionId}} HTTP/1.1\nAuthorization: Bearer {{token}}")
           '(("baseUrl" . "https://api.example.com")
             ("userId" . "12345")
             ("token" . "eyJhbGc...")
             ("userName" . "John Doe")
             ("userEmail" . "john@example.com")
             ("sessionId" . "sess-abc-123"))
           #:include-headers?
           #t)))))

(run-tests!)
