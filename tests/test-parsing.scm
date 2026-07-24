;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 Tom Waddington

;;; test-parsing.scm - request splitting, request line, headers/body split.
;;;
;;; Run from the repo root: steel tests/test-parsing.scm

(require "steel-test/test.scm")
(require "../http2curl.scm")

(deftest request-line
  (testing "method and url, HTTP version ignored"
    (is (= '("curl 'https://api.example.com/users'")
         (http->curl "GET https://api.example.com/users HTTP/1.1" '()))))
  (testing "HTTP version is optional"
    (is (= '("curl 'https://x.test/a'") (http->curl "GET https://x.test/a" '()))))
  (testing "method is passed through verbatim, not upcased"
    (is (= '("curl -X get 'https://x.test/a'") (http->curl "get https://x.test/a HTTP/1.1" '()))))
  (testing "url is not shell quoted"
    (is (= '("curl 'https://x.test/a?b=c&d=e'") (http->curl "GET https://x.test/a?b=c&d=e" '())))))

(deftest empty-requests-filtered
  (testing "empty input"
    (is (= '() (http->curl "" '()))))
  (testing "empty list input"
    (is (= '() (http->curl '() '()))))
  (testing "request line with no url"
    (is (= '() (http->curl "GET" '()))))
  (testing "comment only"
    (is (= '() (http->curl "# only a comment" '())))))

(deftest leading-noise-skipped
  (testing "blank lines before the request line"
    (is (= '("curl 'https://x.test/a'") (http->curl "\n\n\nGET https://x.test/a HTTP/1.1" '()))))
  (testing "hash comment before the request line"
    (is (= '("curl 'https://x.test/a'") (http->curl "# fetch it\nGET https://x.test/a HTTP/1.1" '()))))
  (testing "slash comment before the request line"
    (is (= '("curl 'https://x.test/a'") (http->curl "// fetch it\nGET https://x.test/a HTTP/1.1" '())))))

(deftest separators
  (testing "### splits one string into several requests"
    (is (= '("curl 'https://api.example.com/users'"
             "curl -X POST -H 'Content-Type: application/json' --data-raw '{\"name\":\"Jane\"}' 'https://api.example.com/users'")
         (http->curl
           "GET https://api.example.com/users HTTP/1.1\n\n###\n\nPOST https://api.example.com/users HTTP/1.1\nContent-Type: application/json\n\n{\"name\":\"Jane\"}"
           '()))))
  (testing "leading separator produces no empty request"
    (is (= '("curl 'https://x.test/a'") (http->curl "###\nGET https://x.test/a HTTP/1.1" '()))))
  (testing "consecutive separators produce no empty request"
    (is (= '("curl 'https://x.test/a'" "curl 'https://x.test/b'")
         (http->curl "GET https://x.test/a HTTP/1.1\n###\n###\nGET https://x.test/b HTTP/1.1" '()))))
  (testing "trailing separator produces no empty request"
    (is (= '("curl 'https://x.test/a'") (http->curl "GET https://x.test/a HTTP/1.1\n###\n" '())))))

(deftest headers-and-body
  (testing "blank line ends the header block"
    (is (= '("curl -X POST -H 'X: y' --data-raw 'line1\nline2' 'https://x.test/a'")
         (http->curl "POST https://x.test/a HTTP/1.1\nX: y\n\nline1\nline2" '()))))
  (testing "header value is trimmed, colon needs no following space"
    (is (= '("curl -H 'Accept: application/json' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nAccept:application/json" '()))))
  (testing "no body means no data flag"
    (is (= '("curl -X DELETE -H 'Authorization: Bearer token' 'https://api.example.com/users/123'")
         (http->curl "DELETE https://api.example.com/users/123 HTTP/1.1\nAuthorization: Bearer token"
           '()))))
  (testing "trailing newline is kept in the body"
    (is (= '("curl -X POST -H 'X: y' --data-raw '{\"a\":1}\n' 'https://x.test/a'")
         (http->curl "POST https://x.test/a HTTP/1.1\nX: y\n\n{\"a\":1}\n" '()))))
  (testing "comment between headers is skipped"
    (is (= '("curl -H 'A: 1' -H 'B: 2' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nA: 1\n# note\nB: 2" '()))))
  (testing "slash comment between headers is skipped"
    (is (= '("curl -H 'A: 1' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\n// note\nA: 1" '()))))
  ;; Only the header block is scanned for comments; once the blank line has
  ;; been seen every line is data.
  (testing "comment inside the body is kept"
    (is (= '("curl -X POST --data-raw 'a\n# not a comment here\nb' 'https://x.test/a'")
         (http->curl "POST https://x.test/a HTTP/1.1\n\na\n# not a comment here\nb" '()))))
  (testing "a non-header line that is not a comment still starts the body"
    (is (= '("curl --data-raw 'no colon here' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nno colon here" '())))))

(run-tests!)
