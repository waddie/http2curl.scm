# http2curl

A Steel Scheme library that translates http format requests into curl commands.

## Features

- Parse http format requests (REST Client format)
- Generate valid curl commands with proper shell escaping
- Support for all HTTP methods (GET, POST, PUT, DELETE, PATCH, etc.)
- Variable substitution with `{{varName}}` syntax
- Multiple requests per file (separated by `###`)
- Accepts list of strings (perfect for Helix editor)
- Request bodies (JSON, plain text, multiline)
- External file references (`< filepath`)
- Optional response headers flag (`-i`)
- Single-file library for easy deployment

## Quick Start

```scheme
(require "http2curl.scm")

;; Simple GET request
(http->curl "GET https://api.example.com/users HTTP/1.1" '())
;; => ("curl 'https://api.example.com/users'")

;; POST with JSON and variables
(http->curl
  "POST {{baseUrl}}/users HTTP/1.1
Content-Type: application/json

{\"name\":\"{{userName}}\"}"
  '(("baseUrl" . "https://api.example.com")
    ("userName" . "John Doe")))
;; => ("curl -X POST -H 'Content-Type: application/json' --data-raw '{\"name\":\"John Doe\"}' 'https://api.example.com/users'")

;; Multi-selection (Helix editor)
(http->curl
  '("GET https://api.example.com/users HTTP/1.1"
    "GET https://api.example.com/posts HTTP/1.1"
    "GET https://api.example.com/comments HTTP/1.1")
  '())
;; => ("curl 'https://api.example.com/users'"
;;     "curl 'https://api.example.com/posts'"
;;     "curl 'https://api.example.com/comments'")
```

See [USAGE.md](USAGE.md) for complete documentation and examples.

## Installation

Copy `http2curl.scm` to your project directory or Steel load path.

## Testing

The suite uses [steel-test](https://github.com/waddie/steel-test), which must be
installed first:

```bash
forge pkg install --git https://github.com/waddie/steel-test
```

```bash
sh tests/run-all.sh          # Whole suite
steel tests/test-parsing.scm # One file; exit code is the verdict
```

## License

MIT License - Copyright (c) 2025 Tom Waddington

See [LICENSE](./LICENSE) file for details.
