# goose-semver

[![ci](https://github.com/rekanalar/goose-semver/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-semver/actions/workflows/ci.yml)

Semantic versions for the [Goose](https://github.com/aardappel/goose) programming language: parse, compare, format, bump and match SemVer 2.0.0 versions against npm-style ranges.

## Features

- Parses `MAJOR.MINOR.PATCH` with an optional pre-release and build metadata.
- Compares versions by the precedence rules of the standard.
- Rejects the forms the standard rejects: leading zeros, empty parts, wrong characters.
- Matches ranges with `^`, `~`, x-ranges, hyphen ranges and `||`.
- Bumps versions, names the change between two versions, and reads loose text.
- Picks the best version of a list, sorts a list, and compares two ranges, as npm does.
- Holds the calls of npm `semver` 7.6.1 under their npm names.
- Pure Goose. No C code.

## Install

Put this line in the root file of your program:

```goose
import semver from "rekanalar/goose-semver@v0.4.0";
```

## Example

```goose
import std;
import semver from "rekanalar/goose-semver@v0.4.0";

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
| `compare(a, b)` | -1, 0 or 1: the order of two versions |
| `format(out, v)` | the version written into out |
| `satisfies(v, range)` | true when the version matches the range |
| `valid_range(out, range)` | the strict range written into out, or false |
| `inc(out, v, release, ident, base)` | the next version written into out, or false |
| `diff(a, b)` | `major`, `premajor`, `minor`, `preminor`, `patch`, `prepatch`, `prerelease`, or empty |
| `coerce(s)` | the first number run of the text as a version |
| `clean(out, s)` | the trimmed version without `v`, `=` and build, or false |
| `pre_parts(v)`, `build_parts(v)` | the dotted parts of the field |
| `max_satisfying(versions, range)` | the place of the highest version in the range, or -1 |
| `min_satisfying(versions, range)` | the place of the lowest version in the range, or -1 |
| `sort(order, versions)`, `rsort(order, versions)` | the places in order, written into `order` |
| `compare_build(a, b)` | -1, 0 or 1: precedence, then the build part |
| `gt`, `gte`, `lt`, `lte`, `eq`, `neq` `(a, b)` | the named comparisons of two versions |
| `min_version(out, range)` | the lowest version of the range written into out, or false |
| `intersects(a, b)` | true when one version can fit both ranges |
| `subset(sub, dom)` | true when every version of `sub` fits `dom` |
| `outside(v, range, hilo)` | true when `v` is above (`">"`) or below (`"<"`) the whole range |
| `gtr(v, range)`, `ltr(v, range)` | `outside` with `">"` and with `"<"` |
| `valid(out, s)` | the version text of npm written into out, or false |
| `major(s)`, `minor(s)`, `patch(s)` | the number of the part, or false |
| `prerelease(parts, s)` | the parts of the pre-release written into parts, or false |
| `compare_text(a, b)` | -1, 0 or 1: the order of two texts |
| `cmp(a, op, b)` | true when the two texts hold the order of the operator |
| `rcompare(a, b)` | -1, 0 or 1: the reverse order of two texts |
| `compare_identifiers(a, b)` | -1, 0 or 1: the order of two pre-release parts |
| `rcompare_identifiers(a, b)` | -1, 0 or 1: the reverse order of two pre-release parts |
| `compare_loose(a, b)` | -1, 0 or 1: the order of two texts without the build part |
| `to_comparators(norm, parts, ends, range)` | the sets of the range written into parts, or false |
| `simplify_range(out, versions, range)` | the shorter range text written into out, or false |

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

## Lists and the algebra of ranges

A list is a slice of version texts. Pass `list[..]` for a fixed or a
growable list. A selection gives a place in the list, or -1. A sort
writes the places into `order`. So no result holds a slice of a text.

```goose
let releases = words("1.2.3 1.2.4 2.0.0");
let best = semver::max_satisfying(releases[..], "^1.2.0");   // 1
var order: i64[>..] = [];
semver::sort(order, releases[..]);                           // 0 1 2
```

- `sort` and `rsort` order by precedence, and then by the build part, as
  npm `compareBuild` does. The sort is stable.
- A text that is not a version is skipped by a selection. A sort puts it
  last, in the order of the input.
- `intersects`, `subset`, `min_version` and `outside` follow the code of
  npm 7.6.1. They keep its rules for the null set and the pre-release.
- A range above 16384 bytes, or with more than 1024 `||` alternatives,
  counts as bad. The compare of two ranges tries every pair of
  alternatives, so the limits bound its time.

The differences from npm:

- npm throws on a bad version or a bad range. Here the calls give -1,
  false or no version. No call aborts.
- There is no `includePrerelease` and no `loose` option.

The check against npm: the script `test/make_npm_cases.js` makes
`test/npm_cases.goose` with npm `semver` 7.6.1. The seed is fixed. The file
holds 1510 cases:

- 180 selections, 70 sorts and 120 comparisons.

- 150 `min_version`, 170 `intersects`, 170 `subset` and 160 `outside`.

- 90 `valid`, 90 `compare_text`, 80 identifiers and 90 `cmp`.

- 80 comparators and 60 `simplify_range`.

Each result equals the result of npm.

## Limits

- Numbers are `i64`. A number above 9007199254740991 is not a version.
- A numeric part of a pre-release is a number in npm. It stays a text
  here.
- No loose mode and no `includePrerelease` option.
- `coerce` has no right-to-left mode and no pre-release option.
- `valid_range` does not remove repeated comparators or empty-set
  alternatives. Its text can differ from npm in those cases only.
- `compare_identifiers` compares a number of any length, digit by
  digit. npm reads a number up to 9007199254740991 and rounds a larger
  one.
- `compare_loose` takes the strict form. A text that `parse` refuses
  gives 0. The loose mode of npm reads leading zeros, a leading `=`, and
  a pre-release without a dash.
- The Go helpers `Major` and `MajorMinor` are not there.

## Test

```bash
goose run test/run.goose
goose run examples/parse.goose
goose run examples/ranges.goose
goose run examples/select.goose
goose run examples/npm.goose
```

## License

MIT
