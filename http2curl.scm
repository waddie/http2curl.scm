#!/usr/bin/env steel

;; http2curl.scm
;; A Steel Scheme library to translate .http format requests into curl commands
;;
;; SPDX-License-Identifier: MIT
;; Copyright (c) 2025 Tom Waddington
;;
;; Usage:
;;   (http->curl http-string variables #:include-headers? bool)
;;
;; Returns: List of curl command strings
;;
;; Example:
;;   (http->curl "POST https://api.example.com\nContent-Type: application/json\n\n{\"foo\":\"bar\"}"
;;               '((token . "abc123"))
;;               #:include-headers? #t)
;;   => '("curl -X POST -i -H 'Content-Type: application/json' --data-raw '{\"foo\":\"bar\"}' 'https://api.example.com'")

;; ============================================================================
;; String Utilities
;; ============================================================================

(define (string-trim str)
  "Remove leading and trailing whitespace"
  (if (string? str)
    (trim str)
    str))

(define (string-split-lines str)
  "Split string by newlines into list of strings"
  (split-many str "\n"))

(define (string-starts-with? str prefix)
  "Check if string starts with prefix"
  (if (and (string? str) (string? prefix))
    (starts-with? str prefix)
    #f))

(define (string-empty? str)
  "Check if string is empty or only whitespace"
  (or (not (string? str)) (= (string-length str) 0) (= (string-length (string-trim str)) 0)))

(define (string-index-of str pattern)
  "Find the index of pattern in str, returns #f if not found"
  (if (not (and (string? str) (string? pattern)))
    #f
    (let ([str-len (string-length str)]
          [pat-len (string-length pattern)])
      (if (or (= pat-len 0) (> pat-len str-len))
        #f
        (let loop ([i 0])
          (if (> (+ i pat-len) str-len)
            #f
            (if (equal? (substring str i (+ i pat-len)) pattern)
              i
              (loop (+ i 1)))))))))

;; Note: Steel has a built-in string-join function, so we don't need to define our own

;; ============================================================================
;; Shell Escaping
;; ============================================================================

(define (escape-single-quotes str)
  "Escape single quotes for shell - replace ' with '\\'' "
  (if (not (string? str))
    ""
    (let ([chars (string->list str)])
      (list->string (apply append
                     (map (lambda (c)
                           (if (eq? c #\')
                             (string->list "'\\''")
                             (list c)))
                       chars))))))

;; Every value carried over from the request (url, header, credentials, body,
;; file path) is single quoted. Single quotes are the only shell quoting that
;; suppresses globbing, parameter expansion and command substitution alike, so
;; the value survives being pasted into a shell intact. The method is left bare:
;; it is a single whitespace-delimited token from the request line.
(define (shell-quote str)
  "Quote string for safe shell usage with single quotes"
  (if (not (string? str))
    "''"
    (string-append "'" (escape-single-quotes str) "'")))

;; ============================================================================
;; Variable Expansion
;; ============================================================================

(define (expand-variable-references str variables)
  "Replace all {{varName}} patterns with values from variables alist"
  (if (not (string? str))
    str
    (let loop ([remaining str]
               [result ""])
      (let ([start-pos (string-index-of remaining "{{")])
        (if (not start-pos)
          ;; No more variables to expand
          (string-append result remaining)
          ;; Found a variable reference
          (let ([end-pos (string-index-of (substring remaining start-pos) "}}")])
            (if (not end-pos)
              ;; No closing }}, leave as-is
              (string-append result remaining)
              ;; Extract variable name and look it up
              (let* ([var-start (+ start-pos 2)]
                     [var-end (+ start-pos end-pos)]
                     [var-name (substring remaining var-start var-end)]
                     [var-value (assoc var-name variables)])
                (if var-value
                  ;; Variable found, substitute and continue
                  (loop
                    (substring remaining (+ var-end 2))
                    (string-append result (substring remaining 0 start-pos) (cdr var-value)))
                  ;; Variable not found, leave as-is and continue
                  (loop (substring remaining (+ var-end 2))
                    (string-append result (substring remaining 0 (+ var-end 2)))))))))))))

(define (resolve-variable-values variables)
  "Recursively resolve variable values that reference other variables.
   Continues expanding until no more variable references remain or a fixed point is reached.
   Example: Given ((domain . \"https://example.com\") (baseUrl . \"{{domain}}/api\"))
            Returns ((domain . \"https://example.com\") (baseUrl . \"https://example.com/api\"))"
  (let loop ([vars variables]
             [max-iterations 100]) ; Prevent infinite loops from circular dependencies
    (if (<= max-iterations 0)
      ;; Safety limit reached, return current state
      vars
      ;; Try to expand all variable values
      (let ([expanded-vars (map (lambda (var-pair)
                                 (cons (car var-pair)
                                   (expand-variable-references (cdr var-pair) vars)))
                            vars)])
        ;; Check if anything changed
        (if (equal? expanded-vars vars)
          ;; Fixed point reached, we're done
          vars
          ;; Something changed, continue iterating
          (loop expanded-vars (- max-iterations 1)))))))

;; ============================================================================
;; Request Parsing
;; ============================================================================

(define (parse-requests http-string)
  "Split http-string by ### separators into list of individual request strings"
  (let ([lines (string-split-lines http-string)])
    (let loop ([remaining lines]
               [current '()]
               [requests '()])
      (if (null? remaining)
        ;; Done processing, add last request if any
        (if (null? current)
          (reverse requests)
          (reverse (cons (string-join (reverse current) "\n") requests)))
        ;; Process next line
        (let ([line (car remaining)])
          (if (string-starts-with? (string-trim line) "###")
            ;; Found separator, save current request and start new one
            (if (null? current)
              ;; Empty request, skip it
              (loop (cdr remaining) '() requests)
              ;; Save current request
              (loop (cdr remaining) '() (cons (string-join (reverse current) "\n") requests)))
            ;; Not a separator, add to current request
            (loop (cdr remaining) (cons line current) requests)))))))

(define (split-first str delimiter)
  "Split string on first occurrence of delimiter, returns (before . after) or #f"
  (let ([pos (string-index-of str delimiter)])
    (if pos
      (cons (substring str 0 pos) (substring str (+ pos (string-length delimiter))))
      #f)))

(define (comment-line? line)
  "Check if line is a comment. ### separators are consumed by parse-requests
   before this runs, so a leading # is always a comment here"
  (let ([trimmed (string-trim line)])
    (or (string-starts-with? trimmed "#") (string-starts-with? trimmed "//"))))

(define (parse-request-line line)
  "Parse 'METHOD URL HTTP/1.1' into (method . url), handles optional HTTP version"
  (let* ([trimmed (string-trim line)]
         [parts (split-whitespace trimmed)])
    (if (or (null? parts) (null? (cdr parts)))
      ;; Invalid request line
      (cons "GET" "")
      ;; Extract method and URL, ignore HTTP version if present
      (cons (car parts) (cadr parts)))))

(define (parse-headers-and-body lines)
  "Parse lines into headers and body, separated by blank line
   Returns ((headers . body) where headers is alist and body is string"
  (let loop ([remaining lines]
             [headers '()]
             [in-body #f]
             [body-lines '()])
    (if (null? remaining)
      ;; Done
      (cons (reverse headers) (string-join (reverse body-lines) "\n"))
      ;; Process next line
      (let ([line (car remaining)])
        (if in-body
          ;; Already in body, collect all remaining lines
          (loop (cdr remaining) headers #t (cons line body-lines))
          ;; Still in headers section
          (cond
            ;; Blank line marks start of body
            [(string-empty? line) (loop (cdr remaining) headers #t body-lines)]
            ;; Comment between headers, skip it
            [(comment-line? line) (loop (cdr remaining) headers #f body-lines)]
            ;; Parse as header
            [else
              (let ([split (split-first line ":")])
                (if split
                  ;; Valid header
                  (let ([key (string-trim (car split))]
                        [value (string-trim (cdr split))])
                    (loop (cdr remaining) (cons (cons key value) headers) #f body-lines))
                  ;; Not a valid header, treat as body start
                  (loop (cdr remaining) headers #t (cons line body-lines))))]))))))

(define (parse-single-request request-string)
  "Parse a single .http request into structured data
   Returns: ((method . METHOD) (url . URL) (headers . HEADERS) (body . BODY))"
  (let ([lines (string-split-lines request-string)])
    ;; Skip leading empty lines and comments, but keep the rest
    (let loop ([remaining lines])
      (if (null? remaining)
        ;; Empty request
        (list (cons 'method "GET") (cons 'url "") (cons 'headers '()) (cons 'body ""))
        (let ([line (car remaining)])
          (if (or (string-empty? line) (comment-line? line))
            ;; Skip this line and continue
            (loop (cdr remaining))
            ;; Found first non-empty, non-comment line - this is the request line
            (let* ([request-line-data (parse-request-line line)]
                   [method (car request-line-data)]
                   [url (cdr request-line-data)]
                   [rest-lines (cdr remaining)]
                   [headers-and-body (parse-headers-and-body rest-lines)]
                   [headers (car headers-and-body)]
                   [body (cdr headers-and-body)])
              (list (cons 'method method)
                (cons 'url url)
                (cons 'headers headers)
                (cons 'body body)))))))))

;; ============================================================================
;; Variable Substitution
;; ============================================================================

(define (expand-variables request variables)
  "Expand all {{variable}} references in request using variables alist"
  (let* ([method (cdr (assoc 'method request))]
         [url (cdr (assoc 'url request))]
         [headers (cdr (assoc 'headers request))]
         [body (cdr (assoc 'body request))]
         ;; First, resolve any variable interdependencies
         [resolved-variables (resolve-variable-values variables)]
         ;; Expand URL
         [expanded-url (expand-variable-references url resolved-variables)]
         ;; Expand headers
         [expanded-headers (map (lambda (header)
                                 (cons (car header)
                                   (expand-variable-references (cdr header) resolved-variables)))
                            headers)]
         ;; Expand body
         [expanded-body (expand-variable-references body resolved-variables)])
    (list (cons 'method method)
      (cons 'url expanded-url)
      (cons 'headers expanded-headers)
      (cons 'body expanded-body))))

;; ============================================================================
;; Curl Command Generation
;; ============================================================================

(define (extract-basic-auth headers)
  "Extract Basic auth credentials from Authorization header.
   Returns (credentials . remaining-headers) where credentials is #f or \"username:password\"
   and remaining-headers is the list without the Authorization header"
  (let loop ([remaining headers]
             [result '()]
             [auth-creds #f])
    (if (null? remaining)
      (cons auth-creds (reverse result))
      (let* ([header (car remaining)]
             [key (car header)]
             [value (cdr header)])
        (if (and (string? key) (equal? (string-trim key) "Authorization"))
          ;; Found Authorization header
          (let ([trimmed-value (string-trim value)])
            (if (string-starts-with? trimmed-value "Basic ")
              ;; Extract credentials after "Basic "
              (let ([creds (string-trim (substring trimmed-value 6))])
                ;; Skip this header and save credentials
                (loop (cdr remaining) result creds))
              ;; Not Basic auth, keep the header
              (loop (cdr remaining) (cons header result) auth-creds)))
          ;; Not Authorization header, keep it
          (loop (cdr remaining) (cons header result) auth-creds))))))

(define (headers->curl-flags headers)
  "Convert headers alist to list of -H flags"
  (map (lambda (header)
        (string-append "-H " (shell-quote (string-append (car header) ": " (cdr header)))))
    headers))

(define (body->curl-flag body)
  "Convert body to curl data flag(s)"
  (cond
    [(string-empty? body) '()]
    ;; Check for external file reference: < filepath
    [(string-starts-with? (string-trim body) "<")
      (let ([filepath (string-trim (substring (string-trim body) 1))])
        (list (string-append "-d " (shell-quote (string-append "@" filepath)))))]
    ;; Regular body data
    [else (list (string-append "--data-raw " (shell-quote body)))]))

(define (request->curl request include-headers?)
  "Generate curl command string from parsed and expanded request"
  (let* ([method (cdr (assoc 'method request))]
         [url (cdr (assoc 'url request))]
         [headers (cdr (assoc 'headers request))]
         [body (cdr (assoc 'body request))]
         ;; Extract Basic auth credentials if present
         [auth-result (extract-basic-auth headers)]
         [basic-auth-creds (car auth-result)]
         [remaining-headers (cdr auth-result)]
         ;; Build command parts
         [parts '("curl")])
    ;; Add method flag (skip if GET)
    (let ([parts (if (equal? method "GET")
                  parts
                  (append parts (list (string-append "-X " method))))])
      ;; Add include-headers flag if requested
      (let ([parts (if include-headers?
                    (append parts (list "-i"))
                    parts)])
        ;; Add Basic auth flag if present
        (let ([parts (if basic-auth-creds
                      (append parts (list (string-append "-u " (shell-quote basic-auth-creds))))
                      parts)])
          ;; Add header flags (excluding Authorization if it was Basic auth)
          (let ([parts (append parts (headers->curl-flags remaining-headers))])
            ;; Add body flag
            (let ([parts (append parts (body->curl-flag body))])
              ;; Add URL (at the end)
              (let ([parts (append parts (list (shell-quote url)))])
                ;; Join with spaces
                (string-join parts " ")))))))))

;; ============================================================================
;; Main Entry Point
;; ============================================================================

(define (http->curl http-input variables . rest)
  "Convert .http format requests to curl commands

   Parameters:
     http-input: Either a string or a list of strings containing .http requests
                 - String: Single string with one or more .http requests
                 - List: Multiple strings (e.g., from Helix multi-selections), each with one or more requests
     variables: Association list of variable substitutions
                e.g., '((\"token\" . \"abc123\") (\"baseUrl\" . \"https://api.example.com\"))
     #:include-headers?: Optional keyword argument (default #f), adds -i flag when true

   Returns: List of curl command strings (flattened from all inputs)

   Examples:
     ;; Single string
     (http->curl \"POST https://api.example.com\\nContent-Type: application/json\\n\\n{\\\"foo\\\":\\\"bar\\\"}\"
                 '((\"token\" . \"abc123\"))
                 #:include-headers? #t)

     ;; Multiple strings (Helix multi-selection)
     (http->curl '(\"GET https://api.example.com/users HTTP/1.1\"
                   \"GET https://api.example.com/posts HTTP/1.1\")
                 '()
                 #:include-headers? #f)"
  ;; Parse keyword arguments
  (let ([include-headers?
          (if (and (not (null? rest)) (not (null? (cdr rest))) (equal? (car rest) #:include-headers?))
            (cadr rest)
            #f)])
    ;; Normalize input to a list of strings
    (let ([http-strings (if (string? http-input)
                         (list http-input)
                         http-input)])
      ;; Process each input string and flatten results
      (apply append
        (map (lambda (http-string)
              ;; Main processing pipeline for each string
              (let* ([requests (parse-requests http-string)]
                     [parsed (map parse-single-request requests)]
                     [expanded (map (lambda (req) (expand-variables req variables)) parsed)]
                     ;; Filter out empty requests (those with no URL)
                     [non-empty (filter (lambda (req)
                                         (let ([url (cdr (assoc 'url req))])
                                           (and (string? url) (> (string-length url) 0))))
                                 expanded)])
                (map (lambda (req) (request->curl req include-headers?)) non-empty)))
          http-strings)))))

;; ============================================================================
;; Exports (for Steel module system)
;; ============================================================================

(provide http->curl)
