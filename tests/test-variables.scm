;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 Tom Waddington

;;; test-variables.scm - {{var}} expansion, including variables that
;;; reference other variables.
;;;
;;; Run from the repo root: steel tests/test-variables.scm

(require "steel-test/test.scm")
(require "../http2curl.scm")

(deftest substitution-sites
  (testing "url, header value and body"
    (is (= '("curl -X POST -H 'Authorization: Bearer abc123' -H 'Content-Type: application/json' --data-raw '{\"id\":\"42\"}' 'https://example.com/api/users'")
         (http->curl
           "POST {{baseUrl}}/api/users HTTP/1.1\nAuthorization: Bearer {{token}}\nContent-Type: application/json\n\n{\"id\":\"{{userId}}\"}"
           '(("baseUrl" . "https://example.com") ("token" . "abc123") ("userId" . "42"))))))
  (testing "several references in one line"
    (is (= '("curl 'https://x.test/a/b'")
         (http->curl "GET {{host}}/{{one}}/{{two}} HTTP/1.1"
           '(("host" . "https://x.test") ("one" . "a") ("two" . "b"))))))
  ;; The method is taken from the request line before expansion runs.
  (testing "method is not expanded"
    (is (= '("curl -X {{m}} 'https://x.test/a'")
         (http->curl "{{m}} https://x.test/a HTTP/1.1" '(("m" . "PATCH"))))))
  (testing "empty variable list leaves the request alone"
    (is (= '("curl 'https://x.test/a'") (http->curl "GET https://x.test/a HTTP/1.1" '())))))

(deftest dependent-variables
  (testing "a value referencing another variable"
    (is (= '("curl -X POST -H 'Content-Type: application/json' --data-raw '{\"test\":\"data\"}' 'https://firstgroup.earcu.com/webservices/api/v1/tokenservice.svc/token/'")
         (http->curl
           "POST {{baseUrl}}/api/v1/tokenservice.svc/token/ HTTP/1.1\nContent-Type: application/json\n\n{\"test\":\"data\"}"
           '(("domain" . "https://firstgroup.earcu.com") ("baseUrl" . "{{domain}}/webservices"))))))
  (testing "a chain of three resolves to a fixed point"
    (is (= '("curl 'https://x.test/api/v1/x'")
         (http->curl "GET {{c}}/x HTTP/1.1"
           '(("a" . "https://x.test") ("b" . "{{a}}/api") ("c" . "{{b}}/v1"))))))
  (testing "definition order does not matter"
    (is (= '("curl 'https://x.test/api/v1/x'")
         (http->curl "GET {{c}}/x HTTP/1.1"
           '(("c" . "{{b}}/v1") ("b" . "{{a}}/api") ("a" . "https://x.test"))))))
  ;; Resolution stops after a fixed iteration cap, so a cycle terminates
  ;; rather than hanging, leaving the reference unexpanded.
  (testing "mutually circular values terminate"
    (is (= '("curl '{{a}}'") (http->curl "GET {{a}} HTTP/1.1" '(("a" . "{{b}}") ("b" . "{{a}}"))))))
  (testing "self-referential value terminates"
    (is (= '("curl '{{a}}'") (http->curl "GET {{a}} HTTP/1.1" '(("a" . "{{a}}")))))))

(deftest unresolved-references
  (testing "unknown variable is left in place"
    (is (= '("curl 'https://x.test/{{missing}}'") (http->curl "GET https://x.test/{{missing}} HTTP/1.1" '()))))
  (testing "unknown variable in a header is left in place"
    (is (= '("curl -H 'Authorization: Bearer {{token}}' 'https://x.test/a'")
         (http->curl "GET https://x.test/a HTTP/1.1\nAuthorization: Bearer {{token}}" '()))))
  (testing "opening braces with no closing braces are left in place"
    (is (= '("curl 'https://x.test/{{unclosed'") (http->curl "GET https://x.test/{{unclosed HTTP/1.1" '()))))
  (testing "known and unknown variables in the same string"
    (is (= '("curl 'https://x.test/{{missing}}'")
         (http->curl "GET {{host}}/{{missing}} HTTP/1.1" '(("host" . "https://x.test")))))))

(run-tests!)
