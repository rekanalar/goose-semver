// An example for the semver package.
//
// It parses two versions, compares them, and prints the newer one.
//
// Run with: goose run examples/parse.goose

import std;
import semver from "..";

fn main() {
    let a, oka = semver::parse("1.2.3-alpha.1");
    let b, okb = semver::parse("1.2.3-beta");
    if !oka || !okb { print("the versions did not parse"); return 1; }
    let order = semver::compare(a, b);
    if order < 0 {
        print("1.2.3-alpha.1 comes before 1.2.3-beta");
    } else if order > 0 {
        print("1.2.3-beta comes before 1.2.3-alpha.1");
    } else {
        print("the versions hold the same precedence");
    }

    var out: u8[>..] = [];
    semver::format(out, a);
    print("formatted: ", out);
    return 0;
}
