;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 Tom Waddington

;;; test-curl-generation.scm - flag selection and ordering, shell escaping,
;;; basic auth extraction, external file bodies.
;;;
;;; Run from the repo root: steel tests/test-curl-generation.scm

(require "steel-test/test.scm")
(require "../http2curl.scm")

(deftest method-flag
  (testing "GET omits -X"
    (is (= '("curl 'https://api.example.com/users'")
         (http->curl "GET https://api.example.com/users HTTP/1.1" '()))))
  (testing "other methods get -X"
    (is (= '("curl -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer token123' --data-raw '{\"name\":\"John\",\"email\":\"john@example.com\"}' 'https://api.example.com/users'")
         (http->curl
           "POST https://api.example.com/users HTTP/1.1\nContent-Type: application/json\nAuthorization: Bearer token123\n\n{\"name\":\"John\",\"email\":\"john@example.com\"}"
           '())))))

(deftest include-headers-flag
  (testing "-i is off by default"
    (is (= '("curl 'https://api.example.com/status'")
         (http->curl "GET https://api.example.com/status HTTP/1.1" '()))))
  (testing "-i is added when asked for"
    (is (= '("curl -i 'https://api.example.com/status'")
         (http->curl "GET https://api.example.com/status HTTP/1.1" '() #:include-headers? #t)))))

;; The order below is the output contract: curl, -X, -i, -u, -H, data, url.
(deftest flag-order
  (testing "every flag at once"
    (is (= '("curl -X POST -i -u 'admin:secret' -H 'Accept: application/json' -H 'Content-Type: application/json' --data-raw '{\"a\":1}' 'https://x.test/a'")
         (http->curl
           "POST https://x.test/a HTTP/1.1\nAccept: application/json\nAuthorization: Basic admin:secret\nContent-Type: application/json\n\n{\"a\":1}"
           '()
           #:include-headers?
           #t))))
  (testing "headers keep their source order"
    (is (= '("curl -H 'A: 1' -H 'B: 2' -H 'C: 3' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nA: 1\nB: 2\nC: 3" '()))))
  (testing "url is last"
    (is (= '("curl -X PUT -H 'A: 1' --data-raw 'body' 'https://x.test/a'")
         (http->curl "PUT https://x.test/a HTTP/1.1\nA: 1\n\nbody" '())))))

(deftest basic-auth
  ;; The credentials are passed through verbatim, so the header is expected to
  ;; hold a literal user:password pair rather than a base64 blob.
  (testing "literal credentials become -u 'and' the header is dropped"
    (is (= '("curl -u 'admin:pass123' 'https://api.example.com/protected'")
         (http->curl "GET https://api.example.com/protected HTTP/1.1\nAuthorization: Basic admin:pass123"
           '()))))
  (testing "credentials from variables"
    (is (= '("curl -X POST -u 'john:secret123' -H 'Content-Type: application/json' --data-raw '{\"action\":\"login\"}' 'https://api.example.com/login'")
         (http->curl
           "POST https://api.example.com/login HTTP/1.1\nAuthorization: Basic {{username}}:{{password}}\nContent-Type: application/json\n\n{\"action\":\"login\"}"
           '(("username" . "john") ("password" . "secret123"))))))
  (testing "-u 'is' emitted where the header sat, other headers survive"
    (is (= '("curl -u 'u:p' -H 'Accept: text/plain' -H 'X-Trace: 1' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nAccept: text/plain\nAuthorization: Basic u:p\nX-Trace: 1"
           '()))))
  (testing "a non-Basic Authorization header stays a header"
    (is (= '("curl -H 'Authorization: Bearer tok' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nAuthorization: Bearer tok" '())))))

(deftest escaping
  (testing "single quotes in the body"
    (is (= '("curl -X POST -H 'Content-Type: application/json' --data-raw '{\"message\":\"Hello, '\\''World'\\''!\",\"special\":\"chars & symbols\"}' 'https://httpbin.org/post'")
         (http->curl
           "POST https://httpbin.org/post HTTP/1.1\nContent-Type: application/json\n\n{\"message\":\"Hello, 'World'!\",\"special\":\"chars & symbols\"}"
           '()))))
  (testing "single quotes in a header value"
    (is (= '("curl -H 'X-Note: it'\\''s here' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nX-Note: it's here" '()))))
  (testing "double quotes in a header value need no escaping"
    (is (= '("curl -H 'X-Note: he said \"hi\"' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nX-Note: he said \"hi\"" '()))))
  (testing "backslash in a header value is not doubled"
    (is (= '("curl -H 'X-Path: C:\\temp' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nX-Path: C:\\temp" '()))))
  ;; Single quoting is what keeps these inert when the command is pasted into
  ;; a shell; under the double quotes used previously they would expand.
  (testing "shell expansions in a header value stay literal"
    (is (= '("curl -H 'Authorization: Bearer $TOKEN' -H 'X-Sub: `id`' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nAuthorization: Bearer $TOKEN\nX-Sub: `id`" '()))))
  (testing "shell metacharacters in the url"
    (is (= '("curl 'https://x.test/a?b=c&d=e'") (http->curl "GET https://x.test/a?b=c&d=e" '()))))
  (testing "single quotes in the credentials"
    (is (= '("curl -u 'us'\\''er:p w' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nAuthorization: Basic us'er:p w" '())))))

(deftest external-file-body
  (testing "< filepath becomes -d @filepath"
    (is (= '("curl -X POST -H 'Content-Type: application/json' -d '@data.json' 'https://api.example.com/upload'")
         (http->curl "POST https://api.example.com/upload HTTP/1.1\nContent-Type: application/json\n\n< data.json"
           '()))))
  (testing "surrounding whitespace is trimmed"
    (is (= '("curl -X POST -d '@data.json' 'https://x.test/a'")
         (http->curl "POST https://x.test/a HTTP/1.1\n\n<   data.json  " '()))))
  (testing "the path is expanded like any other body"
    (is (= '("curl -X POST -d '@/tmp/payload.json' 'https://x.test/a'")
         (http->curl "POST https://x.test/a HTTP/1.1\n\n< {{dir}}/payload.json" '(("dir" . "/tmp")))))))

(run-tests!)
