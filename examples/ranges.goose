// An example for the semver package: ranges, bumps and diff.
//
// Run with: goose run examples/ranges.goose

import std;
import semver from "..";

fn main() {
    let v, ok = semver::parse("1.4.2");
    if !ok { return 1; }
    print("1.4.2 satisfies ^1.2.0: ", semver::satisfies(v, "^1.2.0"));
    print("1.4.2 satisfies ~1.3:   ", semver::satisfies(v, "~1.3"));

    var strict: u8[>..] = [];
    if semver::valid_range(strict, "1.2 - 2.3.4 || ^4") { print("strict form: ", strict); }

    var next: u8[>..] = [];
    if semver::inc(next, v, "preminor", "beta") { print("preminor: ", next); }

    let w, ok2 = semver::parse("2.0.0-rc.1");
    if !ok2 { return 1; }
    print("diff: ", semver::diff(v, w));

    let c, ok3 = semver::coerce("release v3.1 build");
    if ok3 { var o: u8[>..] = []; semver::format(o, c); print("coerce: ", o); }
    return 0;
}
