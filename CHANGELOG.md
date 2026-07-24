# Changelog

## [0.3.0]

### Changed

- Every value carried over from the request is now single quoted: URL,
  credentials, header, body, and external file path. Headers were double quoted
  before, which left `$VAR`, backticks and `$(...)` in a header value live when
  the command was pasted into a shell. URLs were not quoted at all, so a query
  string was globbed or split at the `&`
- Comments (`#`, `//`) between headers are skipped instead of being read as the
  start of the body, which previously swallowed every header after them

Both change the generated text, so anything comparing output strings needs
updating:

```scheme
;; Before
"curl -H \"Content-Type: application/json\" https://api.example.com/users?page=2"
;; After
"curl -H 'Content-Type: application/json' 'https://api.example.com/users?page=2'"
```

### Removed

- Unused `needs-quoting?`, `double-quote` and `escape-double-quotes` helpers

### Testing

- Test suite ported to [steel-test](https://github.com/waddie/steel-test): the
  files assert rather than print, and the exit code is the verdict. Run with
  `sh tests/run-all.sh`

## [0.2.0] - Multi-Selection Support

### Added

- Multi-selection support: `http->curl` now accepts either a string or a list of strings
- Each string in the list is processed independently, and all results are flattened into a single list
- Empty selections are automatically filtered out

### Changed

- Function signature updated from `http-string` to `http-input` parameter
- Parameter can now be:
  - `String`: Single string with one or more http requests (backward compatible)
  - `List of Strings`: Multiple strings from multi-selections, each with one or more requests

### Documentation

- Updated `USAGE.md` with multi-selection examples
- Updated `README.md` to highlight multi-selection feature
- Added `test-multi-selection.scm` with comprehensive multi-selection tests

### Examples

**Before (still works):**

```scheme
(http->curl "GET https://api.example.com/users HTTP/1.1" '())
;; => ("curl https://api.example.com/users")
```

**After (new capability):**

```scheme
(http->curl '("GET https://api.example.com/users HTTP/1.1"
              "GET https://api.example.com/posts HTTP/1.1")
            '())
;; => ("curl https://api.example.com/users"
;;     "curl https://api.example.com/posts")
```

### Backward Compatibility

Fully backward compatible - all existing code using string input continues to work

## [0.1.0] - Initial Release

### Features

- Parse http format requests (REST Client format)
- Generate valid curl commands with proper shell escaping
- Support for all HTTP methods (GET, POST, PUT, DELETE, PATCH, etc.)
- Variable substitution with `{{varName}}` syntax
- Multiple requests per file (separated by `###`)
- Request bodies (JSON, plain text, multiline)
- External file references (`< filepath`)
- Optional response headers flag (`-i`)
