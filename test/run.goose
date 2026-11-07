// Tests for the semver package. Run with: goose run test/run.goose
//
// The order tests take their pairs from the SemVer 2.0.0 standard, part 11.

import std;
import semver from "..";

fn expect_parse(s: const u8[:], ma: i32, mi: i32, pa: i32, pre: const u8[:], build: const u8[:]) {
    let v, ok = semver::parse(s);
    assert(ok);
    assert(v.major == ma && v.minor == mi && v.patch == pa);
    assert(v.pre == pre);
    assert(v.build == build);
}

fn test_parse() {
    expect_parse("1.2.3", 1, 2, 3, "", "");
    expect_parse("0.0.0", 0, 0, 0, "", "");
    expect_parse("10.20.30", 10, 20, 30, "", "");
    expect_parse("1.2.3-alpha", 1, 2, 3, "alpha", "");
    expect_parse("1.2.3-alpha.1", 1, 2, 3, "alpha.1", "");
    expect_parse("1.2.3-x.7.z.92", 1, 2, 3, "x.7.z.92", "");
    expect_parse("1.2.3+build.5", 1, 2, 3, "", "build.5");
    expect_parse("1.2.3-alpha+001", 1, 2, 3, "alpha", "001");
    expect_parse("1.2.3-beta+exp.sha.5114f85", 1, 2, 3, "beta", "exp.sha.5114f85");
}

fn test_parse_faults() {
    let v, ok = semver::parse("");
    assert(!ok);
    let v2, ok2 = semver::parse("1");
    assert(!ok2);
    let v3, ok3 = semver::parse("1.2");
    assert(!ok3);
    let v4, ok4 = semver::parse("1.2.3.4");
    assert(!ok4);
    // A leading zero is a fault.
    let v5, ok5 = semver::parse("01.2.3");
    assert(!ok5);
    let v6, ok6 = semver::parse("1.02.3");
    assert(!ok6);
    // An empty part is a fault.
    let v7, ok7 = semver::parse("1.2.-");
    assert(!ok7);
    // A numeric pre-release part may not lead with a zero.
    let v8, ok8 = semver::parse("1.2.3-01");
    assert(!ok8);
    // A numeric part after a dot may not lead with a zero either, but the
    // build metadata may.
    let v9, ok9 = semver::parse("1.2.3-alpha.01");
    assert(!ok9);
    let v9b, ok9b = semver::parse("1.2.3-alpha.0");
    assert(ok9b);
    let v10, ok10 = semver::parse("1.2.3+001");
    assert(ok10);
    // A letter in the core is a fault.
    let v11, ok11 = semver::parse("a.b.c");
    assert(!ok11);
}

fn expect_order(a: const u8[:], b: const u8[:]) {
    let va, oka = semver::parse(a);
    let vb, okb = semver::parse(b);
    assert(oka && okb);
    assert(semver::compare(va, vb) < 0);
    assert(semver::compare(vb, va) > 0);
}

fn expect_same(a: const u8[:], b: const u8[:]) {
    let va, oka = semver::parse(a);
    let vb, okb = semver::parse(b);
    assert(oka && okb);
    assert(semver::compare(va, vb) == 0);
}

fn test_order() {
    // The order pairs from the standard, part 11.
    expect_order("1.0.0-alpha", "1.0.0");
    expect_order("1.0.0-alpha", "1.0.0-alpha.1");
    expect_order("1.0.0-alpha.1", "1.0.0-alpha.beta");
    expect_order("1.0.0-alpha.beta", "1.0.0-beta");
    expect_order("1.0.0-beta", "1.0.0-beta.2");
    expect_order("1.0.0-beta.2", "1.0.0-beta.11");
    expect_order("1.0.0-beta.11", "1.0.0-rc.1");
    expect_order("1.0.0-rc.1", "1.0.0");
    expect_order("2.1.0", "2.2.0");
    expect_order("1.9.9", "2.0.0");
    // The build metadata takes no part in the order.
    expect_same("1.0.0", "1.0.0+build");
    expect_same("1.0.0+a", "1.0.0+b");
}

fn test_format() {
    let v, ok = semver::parse("1.2.3-alpha+build.5");
    assert(ok);
    var out: u8[>..] = [];
    semver::format(out, v);
    assert(out == "1.2.3-alpha+build.5");

    let v2, ok2 = semver::parse("0.1.0");
    assert(ok2);
    var out2: u8[>..] = [];
    semver::format(out2, v2);
    assert(out2 == "0.1.0");
}


// The cases below carry the results of the npm semver package, 7.x. The
// text "NULL" stands for the null of npm.

fn expect_sat(v: const u8[:], r: const u8[:], want: bool) {
    let ver, ok = semver::parse(v);
    assert(ok);
    assert(semver::satisfies(ver, r) == want);
}

fn expect_range(r: const u8[:], want: const u8[:]) {
    var out: u8[>..] = [];
    let ok = semver::valid_range(out, r);
    if want == "NULL" {
        assert(!ok);
        return;
    }
    assert(ok);
    if want == "" { assert(out == "*"); return; }
    assert(out == want);
}

fn expect_inc(v: const u8[:], rel: const u8[:], ident: const u8[:], base: i64, want: const u8[:]) {
    let ver, ok = semver::parse(v);
    assert(ok);
    var out: u8[>..] = [];
    let ok2 = semver::inc(out, ver, rel, ident, base);
    if want == "NULL" {
        assert(!ok2);
        assert(out.len == 0);
        return;
    }
    assert(ok2);
    assert(out == want);
}

fn expect_diff(a: const u8[:], b: const u8[:], want: const u8[:]) {
    let va, oka = semver::parse(a);
    let vb, okb = semver::parse(b);
    assert(oka && okb);
    assert(semver::diff(va, vb) == want);
}

fn expect_coerce(s: const u8[:], want: const u8[:]) {
    let v, ok = semver::coerce(s);
    if want == "NULL" { assert(!ok); return; }
    assert(ok);
    var out: u8[>..] = [];
    semver::format(out, v);
    assert(out == want);
}

fn expect_clean(s: const u8[:], want: const u8[:]) {
    var out: u8[>..] = [];
    let ok = semver::clean(out, s);
    if want == "NULL" { assert(!ok); assert(out.len == 0); return; }
    assert(ok);
    assert(out == want);
}

fn test_parts() {
    let v, ok = semver::parse("1.2.3-alpha.1+b.7");
    assert(ok);
    let p = semver::pre_parts(v);
    assert(p.len == 2 && p[0] == "alpha" && p[1] == "1");
    let b = semver::build_parts(v);
    assert(b.len == 2 && b[1] == "7");
    let v2, ok2 = semver::parse("1.2.3");
    assert(ok2);
    assert(semver::pre_parts(v2).len == 0);
    assert(semver::build_parts(v2).len == 0);
}

fn test_satisfies() {
    expect_sat("1.2.3", "^1.2.3", true);
    expect_sat("2.0.0", "^1.2.3", false);
    expect_sat("1.2.2", "^1.2.3", false);
    expect_sat("1.3.0", "~1.2.3", false);
    expect_sat("1.2.9", "~1.2", true);
    expect_sat("1.9.9", "~1", true);
    expect_sat("2.0.0", "~1", false);
    expect_sat("1.9.9", "1.x", true);
    expect_sat("2.0.0", "1.x", false);
    expect_sat("1.3.0", "1.2.x", false);
    expect_sat("1.2.4", "1.2.3", false);
    expect_sat("1.2.3", ">1.2.3", false);
    expect_sat("1.2.2", "<1.2.3", true);
    expect_sat("1.2.4", "<=1.2.3", false);
    expect_sat("2.0.0", "1.2.3 - 2.0.0", true);
    expect_sat("2.0.1", "1.2.3 - 2.0.0", false);
    expect_sat("1.2.2", "1.2.3 - 2.0.0", false);
    expect_sat("3.0.0", "^1.0.0 || ^2.0.0", false);
    expect_sat("2.5.0", "^1.0.0 || ^2.0.0", true);
    expect_sat("1.2.3-alpha", "^1.2.3", false);
    expect_sat("1.2.3-alpha", ">=1.2.3-alpha <2.0.0", true);
    expect_sat("1.2.3-alpha.2", ">=1.2.3-alpha <2.0.0", true);
    expect_sat("1.2.4-alpha", ">=1.2.3-alpha <2.0.0", false);
    expect_sat("1.0.0", "*", true);
    expect_sat("1.0.0-alpha", "*", false);
    expect_sat("0.3.0", "^0.2.3", false);
    expect_sat("0.2.3", "^0.2.3", true);
    expect_sat("0.0.4", "^0.0.3", false);
    expect_sat("1.0.0", "^0", false);
    expect_sat("0.1.0", "^0", true);
    expect_sat("2.0.0", "1.2.3 - 2", true);
    expect_sat("2.1.0", "1.2.3 - 2", true);
    expect_sat("2.3.5", "1.2 - 2.3.4", false);
    expect_sat("1.3.0", "<=1.2", false);
    expect_sat("1.2.0", "<1.2", false);
    expect_sat("2.0.0", ">1", true);
    expect_sat("1.9.9", ">1", false);
    expect_sat("1.2.3", "1.2.3 - 2.0.0 || 3.0.0", true);
    expect_sat("1.3.0", "~>1.2.3", false);
    expect_sat("1.2.3", "^ 1.2.3", true);
    expect_sat("1.2.3", "> 1.2.2", true);
    expect_sat("1.2.3", ">= 1.2.3", true);
    expect_sat("1.2.3", "not-a-range", false);
    expect_sat("1.2.3", "1.2.3.4", false);
    expect_sat("1.2.3", "1.x.3", false);
    expect_sat("2.0.0-alpha", ">=1.0.0 <2.0.0-0", false);
    expect_sat("1.2.3", "v1.2.3", true);
    expect_sat("1.2.3", "", true);
    expect_sat("1.2.3", "x", true);
    expect_sat("1.2.3", "=1.2.3", true);
}

fn test_valid_range() {
    expect_range("*", "*");
    expect_range("", "*");
    expect_range("1", ">=1.0.0 <2.0.0-0");
    expect_range("1.2", ">=1.2.0 <1.3.0-0");
    expect_range("1.2.3", "1.2.3");
    expect_range(">=1.2.3", ">=1.2.3");
    expect_range("=1.2.3", "1.2.3");
    expect_range("^1.2.3", ">=1.2.3 <2.0.0-0");
    expect_range("^1.2", ">=1.2.0 <2.0.0-0");
    expect_range("^1", ">=1.0.0 <2.0.0-0");
    expect_range("^0.2.3", ">=0.2.3 <0.3.0-0");
    expect_range("^0.0.3", ">=0.0.3 <0.0.4-0");
    expect_range("^0.0", "<0.1.0-0");
    expect_range("^0", "<1.0.0-0");
    expect_range("^0.x", "<1.0.0-0");
    expect_range("^1.2.3-alpha", ">=1.2.3-alpha <2.0.0-0");
    expect_range("~1.2.3", ">=1.2.3 <1.3.0-0");
    expect_range("~1.2", ">=1.2.0 <1.3.0-0");
    expect_range("~1", ">=1.0.0 <2.0.0-0");
    expect_range("~0.0.3", ">=0.0.3 <0.1.0-0");
    expect_range("~>1.2.3", ">=1.2.3 <1.3.0-0");
    expect_range("~0", "<1.0.0-0");
    expect_range("1.x", ">=1.0.0 <2.0.0-0");
    expect_range("1.2.x", ">=1.2.0 <1.3.0-0");
    expect_range("x.x", "*");
    expect_range("1.*", ">=1.0.0 <2.0.0-0");
    expect_range(">1.x", ">=2.0.0");
    expect_range(">=1.x", ">=1.0.0");
    expect_range("<1.x", "<1.0.0-0");
    expect_range("<=1.x", "<2.0.0-0");
    expect_range("=1.x", ">=1.0.0 <2.0.0-0");
    expect_range(">1.2", ">=1.3.0");
    expect_range("<1.2", "<1.2.0-0");
    expect_range("<=1.2", "<1.3.0-0");
    expect_range(">x", "<0.0.0-0");
    expect_range("1.2.3 - 2.0.0", ">=1.2.3 <=2.0.0");
    expect_range("1.2 - 2.3.4", ">=1.2.0 <=2.3.4");
    expect_range("1.2.3 - 2", ">=1.2.3 <3.0.0-0");
    expect_range("1 - 2", ">=1.0.0 <3.0.0-0");
    expect_range("1.2.3-alpha - 2.0.0-beta", ">=1.2.3-alpha <=2.0.0-beta");
    expect_range("x - 2", "<3.0.0-0");
    expect_range("^1.0.0 || ^2.0.0", ">=1.0.0 <2.0.0-0||>=2.0.0 <3.0.0-0");
    expect_range("1.2.3 || 2.0.0", "1.2.3||2.0.0");
    expect_range(">= 1.2.3", ">=1.2.3");
    expect_range("^ 1.2.3", ">=1.2.3 <2.0.0-0");
    expect_range("~ 1.2.3", ">=1.2.3 <1.3.0-0");
    expect_range("> 1.2.3", ">1.2.3");
    expect_range("1.2.3 - 2.0.0 || 3.0.0", ">=1.2.3 <=2.0.0||3.0.0");
    expect_range("v1.2.3", "1.2.3");
    expect_range(">=v1.2.3", ">=1.2.3");
    expect_range("1.2.x-alpha", ">=1.2.0 <1.3.0-0");
    expect_range("not-a-range", "NULL");
    expect_range("1.2.3.4", "NULL");
    expect_range("1.x.3", "NULL");
    expect_range(">=", "NULL");
    expect_range("1.2.3 -", "NULL");
}

fn test_inc() {
    expect_inc("1.2.3", "major", "", 0, "2.0.0");
    expect_inc("1.2.3", "minor", "", 0, "1.3.0");
    expect_inc("1.2.3", "patch", "", 0, "1.2.4");
    expect_inc("1.2.0-5", "major", "", 0, "2.0.0");
    expect_inc("1.0.0-5", "major", "", 0, "1.0.0");
    expect_inc("1.2.0-5", "minor", "", 0, "1.2.0");
    expect_inc("1.2.3-5", "patch", "", 0, "1.2.3");
    expect_inc("1.2.3", "premajor", "beta", 0, "2.0.0-beta.0");
    expect_inc("1.2.3", "preminor", "beta", 0, "1.3.0-beta.0");
    expect_inc("1.2.3", "prepatch", "beta", 0, "1.2.4-beta.0");
    expect_inc("1.2.3", "prerelease", "beta", 0, "1.2.4-beta.0");
    expect_inc("1.2.4-beta.0", "prerelease", "beta", 0, "1.2.4-beta.1");
    expect_inc("1.2.3-alpha.1", "prerelease", "beta", 0, "1.2.3-beta.0");
    expect_inc("1.2.3-alpha.1", "prerelease", "", 0, "1.2.3-alpha.2");
    expect_inc("1.2.3", "prerelease", "", 0, "1.2.4-0");
    expect_inc("1.2.3", "premajor", "", 0, "2.0.0-0");
    expect_inc("1.2.3", "release", "", 0, "NULL");
    expect_inc("1.2.3-rc.1", "release", "", 0, "1.2.3");
    expect_inc("1.2.3-rc.1+b", "patch", "", 0, "1.2.3");
    expect_inc("1.2.3", "prerelease", "beta", 1, "1.2.4-beta.1");
    expect_inc("1.2.3", "prerelease", "beta", -1, "1.2.4-beta");
    expect_inc("1.2.3-beta", "prerelease", "beta", -1, "NULL");
    expect_inc("1.2.3", "bogus", "", 0, "NULL");
    expect_inc("1.2.3", "prerelease", "a.b", 0, "1.2.4-a.b.0");
    expect_inc("1.2.3", "prerelease", "a.01", 0, "NULL");
    expect_inc("1.2.3-beta.5.x", "prerelease", "beta", 0, "1.2.3-beta.6.x");
}

fn test_diff() {
    expect_diff("1.2.3", "1.2.3", "");
    expect_diff("1.2.3", "2.0.0", "major");
    expect_diff("1.2.3", "1.3.0", "minor");
    expect_diff("1.2.3", "1.2.4", "patch");
    expect_diff("1.2.3", "2.0.0-rc.1", "premajor");
    expect_diff("1.2.3", "1.3.0-rc.1", "preminor");
    expect_diff("1.2.3", "1.2.4-rc.1", "prepatch");
    expect_diff("1.2.3-a", "1.2.3-b", "prerelease");
    expect_diff("1.0.0-1", "1.0.0", "major");
    expect_diff("1.0.0-1", "1.1.1", "major");
    expect_diff("1.0.0-1", "2.0.0", "major");
    expect_diff("1.2.0-1", "1.2.0", "minor");
    expect_diff("1.2.3-1", "1.2.3", "patch");
    expect_diff("1.2.0-1", "1.2.1", "patch");
    expect_diff("2.0.0", "1.0.0", "major");
    expect_diff("1.2.3+a", "1.2.3+b", "");
}

fn test_coerce() {
    expect_coerce("1", "1.0.0");
    expect_coerce("1.2", "1.2.0");
    expect_coerce("1.2.3", "1.2.3");
    expect_coerce("v2.3", "2.3.0");
    expect_coerce("  3.4.5.6", "3.4.5");
    expect_coerce("foo 2.1 bar", "2.1.0");
    expect_coerce("version 1.2.3-beta", "1.2.3");
    expect_coerce("a1.b2", "1.0.0");
    expect_coerce("none", "NULL");
    expect_coerce("01.2.3", "NULL");
    expect_coerce("1.02.3", "NULL");
    expect_coerce("1.2.3.4.5", "1.2.3");
    expect_coerce("x1.2.y", "1.2.0");
    expect_coerce("1234567890123456789.1", "1.0.0");
    expect_coerce("1.", "1.0.0");
    expect_coerce("1..2", "1.0.0");
}

fn test_clean() {
    expect_clean("  =v1.2.3   ", "1.2.3");
    expect_clean("1.2.3", "1.2.3");
    expect_clean("v1.2.3+b", "1.2.3");
    expect_clean("=1.2.3-rc.1", "1.2.3-rc.1");
    expect_clean("1.2", "NULL");
    expect_clean("vv1.2.3", "1.2.3");
    expect_clean("1.2.3 junk", "NULL");
    expect_clean("", "NULL");
    expect_clean("v=1.2.3", "1.2.3");
}

fn main() {
    test_parse();
    test_parse_faults();
    test_order();
    test_format();
    test_parts();
    test_satisfies();
    test_valid_range();
    test_inc();
    test_diff();
    test_coerce();
    test_clean();
    print("all tests passed");
    return 0;
}
