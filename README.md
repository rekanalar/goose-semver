# goose-semver

[![ci](https://github.com/rekanalar/goose-semver/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-semver/actions/workflows/ci.yml)

Semantic versions for the [Goose](https://github.com/aardappel/goose) programming language: parse, compare, format, bump and match SemVer 2.0.0 versions against npm-style ranges.

## Features

- Parses `MAJOR.MINOR.PATCH` with an optional pre-release and build metadata.
- Compares versions by the precedence rules of the standard.
- Rejects the forms the standard rejects: leading zeros, empty parts, wrong characters.
- Matches ranges with `^`, `~`, x-ranges, hyphen ranges and `||`.
- Bumps versions, names the change between two versions, and reads loose text.
- Pure Goose. No C code.

## Install

Put this line in the root file of your program:

```goose
import semver from "rekanalar/goose-semver@v0.2.0";
```

## Example

```goose
import std;
import semver from "rekanalar/goose-semver@v0.2.0";

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
| `satisfies(v, range)` | true when the version matches the range |
| `valid_range(out, range)` | the strict range written into out, or false |
| `inc(out, v, release, ident, base)` | the next version written into out, or false |
| `diff(a, b)` | `major`, `premajor`, `minor`, `preminor`, `patch`, `prepatch`, `prerelease`, or empty |
| `coerce(s)` | the first number run of the text as a version |
| `clean(out, s)` | the trimmed version without `v`, `=` and build, or false |
| `pre_parts(v)`, `build_parts(v)` | the dotted parts of the field |

The fields `major`, `minor`, `patch`, `pre` and `build` of a version are
the accessors. The pre-release and build fields refer to the text that
the parse read. They stay valid only as long as that text.

The build metadata takes no part in the order. A version with a
pre-release comes before one without.

## Ranges

`satisfies` reads `>`, `>=`, `<`, `<=`, `=`, `^`, `~`, `~>`, `x`, `X`,
`*`, `a - b` and `||`. A version with a pre-release matches only when a
comparator of the same major, minor and patch names a pre-release. So
`1.2.3-alpha` does not match `^1.2.3`. A bad range matches nothing.

`inc` takes the release types `major`, `minor`, `patch`, `premajor`,
`preminor`, `prepatch`, `prerelease` and `release`. Give `base` 0 or 1
for the first pre-release number, or -1 for none.

## Limits

- Numbers are `i32`. A number above 2147483647 is not a version.
- No loose mode and no `includePrerelease` option. `parse` rejects a
  leading `v`. Use `clean` or `coerce` for that.
- `coerce` has no right-to-left mode and no pre-release option.
- `valid_range` does not remove repeated comparators or empty-set
  alternatives. Its text can differ from npm in those cases only.
- No `intersects`, `subset`, `max_satisfying` or `sort` yet.
- The Go helpers `Major` and `MajorMinor` are not there.

## Test

```bash
goose run test/run.goose
goose run examples/parse.goose
goose run examples/ranges.goose
```

## License

MIT
