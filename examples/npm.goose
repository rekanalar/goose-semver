// An example for the calls that npm semver has.
//
// It shows the calls of the v0.4.0 release.
//
// Run with: goose run examples/npm.goose

import std;
import semver from "..";

fn main() {
    // The version text of npm. A bad text gives false.
    var text: u8[>..] = [];
    if semver::valid(text, "v1.2.3") { print("valid: ", text); }

    // The numbers of a version.
    let major, ok1 = semver::major("1.2.3-beta.1");
    let minor, ok2 = semver::minor("1.2.3-beta.1");
    let patch, ok3 = semver::patch("1.2.3-beta.1");
    if ok1 && ok2 && ok3 {
        print("numbers: ", major, ".", minor, ".", patch);
    }

    // The parts of a pre-release.
    var parts: const u8[:][>..] = [];
    if semver::prerelease(parts, "1.2.3-beta.1") {
        print("pre-release: ", parts[0]);
    }

    // The comparison of two texts. The result is -1, 0 or 1.
    print("compare: ", semver::compare_text("1.2.3", "1.10.0"));
    print("loose: ", semver::compare_loose("1.2.3+a", "1.2.3+b"));
    print("rcompare: ", semver::rcompare("1.2.3", "1.10.0"));

    // The comparison of two pre-release parts.
    print("identifiers: ", semver::compare_identifiers("2", "10"));

    // The comparison with an operator.
    print("cmp: ", semver::cmp("1.2.3", ">=", "1.2.3"));

    // The comparators of a range.
    var norm: u8[>..] = [];
    var comps: const u8[:][>..] = [];
    var ends: i64[>..] = [];
    if semver::to_comparators(norm, comps, ends, "^1.2.3") {
        var line: u8[>..] = [];
        for p, i in comps {
            if i > 0 { line.push(' '); }
            line.append(p);
        }
        print("comparators: ", line);
    }

    // The range that keeps the same versions in a shorter text.
    var range: u8[>..] = [];
    var versions: const u8[:][>..] = [];
    versions.push("1.0.0");
    versions.push("1.1.0");
    versions.push("2.0.0");
    if semver::simplify_range(range, versions[..], ">=1.0.0") {
        print("simplified: ", range);
    }
    return 0;
}
