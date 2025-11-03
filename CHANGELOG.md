# Changelog

## [1.1.0] - Multi-Selection Support

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

## [1.0.0] - Initial Release

### Features

- Parse http format requests (REST Client format)
- Generate valid curl commands with proper shell escaping
- Support for all HTTP methods (GET, POST, PUT, DELETE, PATCH, etc.)
- Variable substitution with `{{varName}}` syntax
- Multiple requests per file (separated by `###`)
- Request bodies (JSON, plain text, multiline)
- External file references (`< filepath`)
- Optional response headers flag (`-i`)
