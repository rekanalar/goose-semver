# goose-semver

[![ci](https://github.com/rekanalar/goose-semver/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-semver/actions/workflows/ci.yml)

Semantic versions for Goose: parse, compare, and format SemVer 2.0.0 strings.

## Features

- Parses `MAJOR.MINOR.PATCH` with an optional pre-release and build metadata.
- Compares versions by the precedence rules of the standard.
- Rejects the forms the standard rejects: leading zeros, empty parts, wrong characters.
- Pure Goose. No C code.

## Install

Put this line in the root file of your program:

```goose
import semver from "rekanalar/goose-semver@v0.1.1";
```

## Example

```goose
import std;
import semver from "rekanalar/goose-semver@v0.1.1";

fn main() {
    let a, ok = semver::parse("1.2.3-alpha.1");
    let b, ok2 = semver::parse("1.2.3");
    if ok && ok2 && semver::compare(a, b) < 0 {
        print("the pre-release comes first");
    }
    return 0;
}
```

## Functions

| Function | Result |
|---|---|
| `parse(s)` | the version and whether the text holds one |
| `compare(a, b)` | a negative number, zero, or a positive one |
| `format(out, v)` | the version written into out |

The pre-release and build fields of a parsed version refer to the text
that the parse read. They stay valid only as long as that text.

The build metadata takes no part in the order. A version with a
pre-release comes before one without.

## Test

```bash
goose run test/run.goose
goose run examples/parse.goose
```

## License

MIT
