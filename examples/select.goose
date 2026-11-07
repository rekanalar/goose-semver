// An example for the lists and the ranges of the semver package.
//
// It picks the best version of a release list, sorts the list, and asks
// questions about ranges.
//
// Run with: goose run examples/select.goose

import std;
import semver from "..";

fn main() {
    let releases = words("1.2.3 1.2.4 1.3.0-beta.1 2.0.0 not-a-version");

    // The place of the highest version that the range accepts.
    let best = semver::max_satisfying(releases[..], "^1.2.0");
    if best < 0 { return 1; }
    print("best for ^1.2.0: ", releases[best]);

    // The places in order, lowest first. A bad text goes last.
    var order: i64[>..] = [];
    semver::sort(order, releases[..]);
    var line: u8[>..] = [];
    for p, i in order {
        if i > 0 { line.push(' '); }
        line.append(releases[p]);
    }
    print("sorted: ", line);

    // The lowest version that a range accepts.
    var low: u8[>..] = [];
    if semver::min_version(low, ">1.2.3") { print("lowest for >1.2.3: ", low); }

    // Two questions about two ranges.
    print("^1.2.0 inside ^1.0.0: ", semver::subset("^1.2.0", "^1.0.0"));
    print("^1.0.0 meets >=1.5.0: ", semver::intersects("^1.0.0", ">=1.5.0"));

    // Where a version lies against a range.
    let v, ok = semver::parse("2.0.0");
    if !ok { return 1; }
    print("2.0.0 above ^1.0.0: ", semver::gtr(v, "^1.0.0"));
    return 0;
}
