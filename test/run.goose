// Tests for the semver package. Run with: goose run test/run.goose
//
// The order tests take their pairs from the SemVer 2.0.0 standard, part 11.

import std;
import os;
import semver from "..";
import npm_cases;

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

// ---- lists, ranges and the algebra of ranges ----------------------------

fn place(list: const u8[:], range: const u8[:], want_max: bool) -> i64 {
    let vs = words(list);
    if want_max { return semver::max_satisfying(vs[..], range); }
    return semver::min_satisfying(vs[..], range);
}

fn test_select() {
    assert(place("1.2.3 1.2.4 2.0.0", "^1.2.0", true) == 1);
    assert(place("1.2.3 1.2.4 2.0.0", "^1.2.0", false) == 0);
    // A text that is not a version is skipped.
    assert(place("bad 1.2.3 1.2 x.y.z", "*", true) == 1);
    assert(place("bad 1.2.3 1.2 x.y.z", "*", false) == 1);
    // No version fits, a bad range, an empty list: -1.
    assert(place("1.2.3 2.0.0", ">=3.0.0", true) == -1);
    assert(place("1.2.3 2.0.0", "not a range", true) == -1);
    assert(place("1.2.3 2.0.0", "not a range", false) == -1);
    assert(place("", "*", true) == -1);
    assert(place("", "*", false) == -1);
    // An equal version does not replace an earlier one.
    assert(place("1.2.3+a 1.2.3+b", "*", true) == 0);
    assert(place("1.2.3+a 1.2.3+b", "*", false) == 0);
    // A pre-release follows the rule of satisfies.
    assert(place("1.3.0-beta.1 1.2.0", "^1.2.0", true) == 1);
    assert(place("1.3.0-beta.1 1.2.0", "^1.3.0-0", true) == 0);
}

fn ordered(list: const u8[:], desc: bool) -> u8[>..] {
    let vs = words(list);
    var order: i64[>..] = [];
    if desc { semver::rsort(order, vs[..]); } else { semver::sort(order, vs[..]); }
    var s: u8[>..] = [];
    for p, i in order {
        if i > 0 { s.push(' '); }
        s.append(vs[p]);
    }
    return s;
}

fn test_sort() {
    assert(ordered("1.0.0 1.2.0 1.1.0", false)[..] == "1.0.0 1.1.0 1.2.0");
    assert(ordered("1.0.0 1.2.0 1.1.0", true)[..] == "1.2.0 1.1.0 1.0.0");
    // The build part decides between equal versions.
    assert(ordered("1.0.0+b 1.0.0+a 1.0.0", false)[..] == "1.0.0 1.0.0+a 1.0.0+b");
    assert(ordered("1.0.0+a.10 1.0.0+a.2", false)[..] == "1.0.0+a.2 1.0.0+a.10");
    // A pre-release comes first.
    assert(ordered("1.0.0 1.0.0-rc.1 1.0.0-alpha", false)[..] == "1.0.0-alpha 1.0.0-rc.1 1.0.0");
    // A text that is not a version goes last, in the order of the input.
    assert(ordered("2.0.0 bad 1.0.0 worse", false)[..] == "1.0.0 2.0.0 bad worse");
    assert(ordered("2.0.0 bad 1.0.0 worse", true)[..] == "2.0.0 1.0.0 bad worse");
    // An empty list, and a list of one.
    assert(ordered("", false).len == 0);
    assert(ordered("1.0.0", true)[..] == "1.0.0");
}

fn test_named_compare() {
    let a, _ = semver::parse("1.2.3");
    let b, _ = semver::parse("1.2.4");
    let c, _ = semver::parse("1.2.3+b");
    assert(semver::lt(a, b) && semver::lte(a, b) && semver::neq(a, b));
    assert(!semver::gt(a, b) && !semver::gte(a, b) && !semver::eq(a, b));
    assert(semver::eq(a, c) && semver::gte(a, c) && semver::lte(a, c));
    assert(!semver::neq(a, c) && !semver::gt(a, c) && !semver::lt(a, c));
    assert(semver::compare_build(a, c) < 0);
    assert(semver::compare_build(c, a) > 0);
    assert(semver::compare_build(a, a) == 0);
}

fn min_of(range: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    let ok = semver::min_version(out, range);
    if !ok { assert(out.len == 0); }
    return out;
}

fn test_range_algebra() {
    assert(min_of("^1.2.3")[..] == "1.2.3");
    assert(min_of(">1.2.3")[..] == "1.2.4");
    assert(min_of(">1.0.0-beta")[..] == "1.0.0-beta.0");
    assert(min_of("*")[..] == "0.0.0");
    assert(min_of("<0.0.0").len == 0);
    assert(min_of(">=2.0.0 <1.0.0").len == 0);
    assert(min_of("not a range").len == 0);
    assert(semver::intersects("^1.2.0", ">=1.5.0"));
    assert(!semver::intersects("<1.0.0", ">1.0.0"));
    assert(semver::intersects("*", "1.2.3"));
    assert(!semver::intersects("^1.0.0 || ^3.0.0", "^2.0.0"));
    assert(semver::subset("^1.2.0", "^1.0.0"));
    assert(!semver::subset("^1.0.0", "^1.2.0"));
    assert(semver::subset("1.2.3", "^1.0.0"));
    assert(semver::subset("^1.0.0 || ^2.0.0", ">=1.0.0 <3.0.0"));
    assert(semver::subset("^1.0.0", "*"));
    assert(!semver::subset("*", "^1.0.0"));
    // The same text is a subset of itself.
    assert(semver::subset("^1.2.3", "^1.2.3"));
}

fn test_outside() {
    let hi, _ = semver::parse("2.0.0");
    let mid, _ = semver::parse("1.5.0");
    let lo, _ = semver::parse("0.1.0");
    assert(semver::gtr(hi, "^1.0.0") && !semver::ltr(hi, "^1.0.0"));
    assert(semver::ltr(lo, "^1.0.0") && !semver::gtr(lo, "^1.0.0"));
    assert(!semver::gtr(mid, "^1.0.0") && !semver::ltr(mid, "^1.0.0"));
    assert(semver::outside(hi, "^1.0.0", ">"));
    assert(semver::outside(lo, "^1.0.0", "<"));
}

// A bad range, a bad version or a bad direction gives the neutral result.
// No call aborts.
fn test_no_abort() {
    let v, _ = semver::parse("1.0.0");
    let bad = ["", "bad", "1.2.3.4", "^", ">=", "||", "1.x.3", "99999999999.0.0", ">0.0.2147483647"];
    for r in bad {
        place("1.0.0 bad", r, true);
        place("1.0.0 bad", r, false);
        var out: u8[>..] = [];
        semver::min_version(out, r);
        semver::intersects(r, "*");
        semver::intersects("*", r);
        semver::subset(r, "*");
        semver::subset("*", r);
        semver::gtr(v, r);
        semver::ltr(v, r);
    }
    assert(!semver::intersects("bad", "*"));
    assert(!semver::subset("bad", "*"));
    assert(!semver::gtr(v, "bad"));
    assert(!semver::ltr(v, "bad"));
    assert(!semver::outside(v, "^1.0.0", "x"));
    assert(!semver::outside(v, "^1.0.0", ""));
    var out: u8[>..] = [];
    assert(!semver::min_version(out, "bad"));
    assert(out.len == 0);
}

fn repeat(unit: const u8[:], n: i64) -> u8[>..] {
    var s: u8[>..] = [];
    for i in 0..n { s.append(unit); }
    return s;
}

// The seconds that a call may take on hostile input.
const HOSTILE_NS: i64 = 2000000000;

fn test_hostile() {
    let t0 = clock_ns();
    // A range above the limits counts as bad.
    let many = repeat("1.0.0 || ", 10000);
    assert(many.len > semver::MAX_RANGE_BYTES);
    assert(place("1.0.0", many[..], true) == -1);
    assert(!semver::intersects(many[..], "*"));
    assert(!semver::subset(many[..], "*"));
    assert(!semver::subset("*", many[..]));
    var out: u8[>..] = [];
    assert(!semver::min_version(out, many[..]));
    // More alternatives than the limit, in few bytes.
    var dense = repeat("1||", 1500);
    dense.append("1");
    assert(dense.len < semver::MAX_RANGE_BYTES);
    assert(place("1.0.0", dense[..], true) == -1);
    assert(clock_ns() - t0 < HOSTILE_NS);

    // Exactly the limit: every pair of alternatives is tried.
    let t1 = clock_ns();
    let edge = repeat("1.0.0||", 1023);
    var edge2: u8[>..] = [];
    edge2.append(edge[..]);
    edge2.append("2.0.0");
    assert(semver::intersects(edge2[..], "2.0.0"));
    assert(!semver::intersects(edge2[..], "3.0.0"));
    assert(!semver::subset(edge2[..], "1.0.0"));
    assert(semver::subset(edge2[..], ">=1.0.0 <3.0.0"));
    // One alternative more than the limit: the range counts as bad.
    var over: u8[>..] = [];
    over.append(edge[..]);
    over.append("1.0.0||2.0.0");
    assert(!semver::intersects(over[..], "2.0.0"));
    assert(clock_ns() - t1 < HOSTILE_NS);

    // A set of many comparators.
    let t2 = clock_ns();
    let wide = repeat(">=1.0.0 ", 2000);
    assert(wide.len < semver::MAX_RANGE_BYTES);
    assert(place("1.5.0", wide[..], true) == 0);
    assert(semver::intersects(wide[..], wide[..]));
    assert(semver::subset(wide[..], ">=1.0.0"));
    assert(clock_ns() - t2 < HOSTILE_NS);

    // A list of many texts.
    let t3 = clock_ns();
    var list: u8[>..] = [];
    for i in 0..10000 {
        if i > 0 { list.push(' '); }
        format(list, i % 50);
        list.append(".");
        format(list, i % 7);
        list.append(".");
        format(list, i);
    }
    let vs = words(list[..]);
    assert(vs.len == 10000);
    assert(semver::max_satisfying(vs[..], "^3.0.0") >= 0);
    assert(semver::min_satisfying(vs[..], "^3.0.0") >= 0);
    var order: i64[>..] = [];
    semver::sort(order, vs[..]);
    assert(order.len == 10000);
    var i: i64 = 1;
    while i < order.len {
        let a, _ = semver::parse(vs[order[i - 1]]);
        let b, _ = semver::parse(vs[order[i]]);
        assert(semver::compare_build(a, b) <= 0);
        i += 1;
    }
    semver::rsort(order, vs[..]);
    assert(order.len == 10000);
    assert(clock_ns() - t3 < HOSTILE_NS);
}

fn test_big_numbers() {
    // A pre-release number above 2147483647 must still order right.
    let a, ok1 = semver::parse("1.0.0-3000000000");
    let b, ok2 = semver::parse("1.0.0-3000000001");
    assert(ok1 && ok2);
    assert(semver::compare(a, b) == -1);
    assert(semver::compare(b, a) == 1);
    // A big number comes before a text.
    let c, _ = semver::parse("1.0.0-3000000000");
    let d, _ = semver::parse("1.0.0-alpha");
    assert(semver::compare(c, d) == -1);
    // A big number against a small one.
    let e, _ = semver::parse("1.0.0-3000000001");
    let f, _ = semver::parse("1.0.0-1");
    assert(semver::compare(e, f) == 1);
    // The exact number of a comparison.
    let g, _ = semver::parse("1.0.0");
    let h, _ = semver::parse("10.0.0");
    assert(semver::compare(g, h) == -1);
    assert(semver::compare(g, g) == 0);
    assert(semver::compare(h, g) == 1);
    // A version with a big number parses.
    let i, ok3 = semver::parse("2147483648.0.0");
    assert(ok3);
    assert(i.major == 2147483648);
    let j, ok4 = semver::parse("9007199254740991.0.0");
    assert(ok4);
    assert(j.major == 9007199254740991);
    // A number above the limit of npm is a fault.
    let k, ok5 = semver::parse("9007199254740992.0.0");
    assert(!ok5);
    // A parse reads a leading v and the space around the text.
    let l, ok6 = semver::parse("v1.2.3");
    assert(ok6);
    assert(l.major == 1 && l.minor == 2 && l.patch == 3);
    let m, ok7 = semver::parse(" 1.2.3 ");
    assert(ok7);
    assert(m.major == 1 && m.minor == 2 && m.patch == 3);
    // A leading = is still a fault.
    let n, ok8 = semver::parse("=1.2.3");
    assert(!ok8);
}

fn test_length_limit() {
    // npm refuses a text above 256 bytes, and reads one of 256 bytes.
    var ok_text: u8[>..] = [];
    ok_text.append("1.0.0-");
    for i in 0..250 { ok_text.push('a'); }
    assert(ok_text.len == 256);
    let a, ok1 = semver::parse(ok_text[..]);
    assert(ok1);
    ok_text.push('a');
    let b, ok2 = semver::parse(ok_text[..]);
    assert(!ok2);
    // The limit counts the space around the text, as npm does.
    var padded: u8[>..] = [];
    for i in 0..300 { padded.push(' '); }
    padded.append("1.0.0");
    let c, ok3 = semver::parse(padded[..]);
    assert(!ok3);
}

fn test_big_pre_release() {
    // A pre-release with a big number raises to the next number.
    let a, ok1 = semver::parse("1.0.0-3000000000");
    assert(ok1);
    var out: u8[>..] = [];
    assert(semver::inc(out, a, "prerelease", "", 0));
    assert(out == "1.0.0-3000000001");
    // A number at the limit of npm or above stays a text, as npm does.
    let big, okbig = semver::parse("1.0.0-99999999999999999999");
    assert(okbig);
    out.clear();
    assert(semver::inc(out, big, "prerelease", "", 0));
    assert(out == "1.0.0-99999999999999999999.0");
    let at_limit, oklim = semver::parse("1.0.0-9007199254740991");
    assert(oklim);
    out.clear();
    assert(semver::inc(out, at_limit, "prerelease", "", 0));
    assert(out == "1.0.0-9007199254740991.0");
    // An earlier number rises when the last one is too big.
    let two, oktwo = semver::parse("1.0.0-5.99999999999999999999");
    assert(oktwo);
    out.clear();
    assert(semver::inc(out, two, "prerelease", "", 0));
    assert(out == "1.0.0-6.99999999999999999999");
    // A list with big pre-release numbers sorts in the order of npm.
    var list: const u8[:][>..] = [];
    list.push("1.0.0-3000000001");
    list.push("1.0.0-3000000000");
    var order: i64[>..] = [];
    semver::sort(order, list[..]);
    assert(order.len == 2);
    assert(order[0] == 1);
    assert(order[1] == 0);
    // A range with a big pre-release number gives the answer of npm.
    assert(semver::satisfies(a, ">=1.0.0-3000000000"));
    let b, ok2 = semver::parse("1.0.0-3000000001");
    assert(ok2);
    assert(semver::satisfies(b, ">=1.0.0-3000000000"));
    assert(!semver::satisfies(a, ">=1.0.0-3000000001"));
}

fn test_new_call_faults() {
    // An operator that npm refuses gives no result.
    assert(!semver::cmp("1.2.3", "~>", "1.2.3"));
    assert(!semver::cmp("1.2.3", "''", "1.2.3"));
    // The empty operator compares the versions.
    assert(semver::cmp("1.2.3", "", "1.2.3"));
    // The text operators read the text itself, as npm does.
    assert(semver::cmp("1.2.3", "===", "1.2.3"));
    assert(!semver::cmp("v1.2.3", "===", "1.2.3"));
    // A text that holds no version gives no result.
    assert(!semver::cmp("not-a-version", "==", "1.2.3"));
    assert(!semver::cmp("1.2.3", "==", "not-a-version"));
    // A version without a pre-release gives an empty list.
    var parts: const u8[:][>..] = [];
    assert(!semver::prerelease(parts, "1.2.3"));
    assert(parts.len == 0);
    // A range that is not a range gives no result.
    var norm: u8[>..] = [];
    var comps: const u8[:][>..] = [];
    var ends: i64[>..] = [];
    assert(!semver::to_comparators(norm, comps, ends, "not a range"));
    var versions: const u8[:][>..] = [];
    versions.push("1.0.0");
    var range: u8[>..] = [];
    assert(!semver::simplify_range(range, versions[..], "not a range"));
}

fn test_npm_calls() {
    // valid gives the version text of npm.
    var out: u8[>..] = [];
    assert(semver::valid(out, "1.2.3"));
    assert(out == "1.2.3");
    out.clear();
    assert(semver::valid(out, "v1.2.3"));
    assert(out == "1.2.3");
    out.clear();
    assert(!semver::valid(out, "1.2"));
    // The accessors take a text.
    let ma, ok1 = semver::major("1.2.3");
    assert(ok1 && ma == 1);
    let mi, ok2 = semver::minor("1.2.3");
    assert(ok2 && mi == 2);
    let pa, ok3 = semver::patch("1.2.3");
    assert(ok3 && pa == 3);
    // cmp compares two texts with an operator.
    assert(semver::cmp("1.2.3", "<", "2.0.0"));
    assert(semver::cmp("1.2.3", "===", "1.2.3"));
    assert(!semver::cmp("1.2.3", ">", "2.0.0"));
    // rcompare gives the reverse of compare.
    assert(semver::rcompare("1.0.0", "2.0.0") == 1);
    assert(semver::rcompare("1.0.0", "1.0.0") == 0);
    // compareIdentifiers compares two pre-release parts.
    assert(semver::compare_identifiers("1", "a") == -1);
    assert(semver::compare_identifiers("01", "1") == 0);
    assert(semver::compare_identifiers("a", "b") == -1);
    assert(semver::rcompare_identifiers("1", "2") == 1);
    // compareLoose ignores the build part and the leading v.
    assert(semver::compare_loose("1.2.3", "v1.2.4") == -1);
    assert(semver::compare_loose("01.2.3", "1.2.3") == 0);
    // toComparators gives the parts of a range and the ends of the sets.
    var norm: u8[>..] = [];
    var parts: const u8[:][>..] = [];
    var ends: i64[>..] = [];
    assert(semver::to_comparators(norm, parts, ends, "^1.2.3 || >=4"));
    assert(parts.len == 3);
    assert(parts[0] == ">=1.2.3");
    assert(parts[1] == "<2.0.0-0");
    assert(parts[2] == ">=4.0.0");
    assert(ends.len == 2);
    assert(ends[0] == 2);
    assert(ends[1] == 3);
    // simplifyRange gives the range text of npm.
    var versions: const u8[:][>..] = [];
    versions.push("1.0.0");
    versions.push("1.2.0");
    versions.push("3.0.0");
    versions.push("5.0.0");
    var range: u8[>..] = [];
    assert(semver::simplify_range(range, versions[..], "1.x || >=2.5.0 || 5.0.0 - 7.2.3"));
    assert(range == "*");
    // A run in the middle of the list gives two ranges.
    var four: const u8[:][>..] = [];
    four.push("1.0.0");
    four.push("1.2.0");
    four.push("2.0.0");
    four.push("3.0.0");
    range.clear();
    assert(semver::simplify_range(range, four[..], "1.0.0 - 1.2.0 || >=3.0.0"));
    assert(range == "<=1.2.0 || >=3.0.0");
    // npm keeps the shorter of the two texts.
    range.clear();
    assert(semver::simplify_range(range, four[..], "1.x || >=3.0.0"));
    assert(range == "1.x || >=3.0.0");
    // One version in the range gives the version.
    var one: const u8[:][>..] = [];
    one.push("1.0.0");
    one.push("1.2.0");
    range.clear();
    assert(semver::simplify_range(range, one[..], "1.0.0"));
    assert(range == "1.0.0");
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
    test_select();
    test_sort();
    test_named_compare();
    test_range_algebra();
    test_outside();
    test_no_abort();
    test_hostile();
    test_big_numbers();
    test_length_limit();
    test_big_pre_release();
    test_new_call_faults();
    test_npm_calls();
    npm_cases::check_select();
    npm_cases::check_sort();
    npm_cases::check_compare();
    npm_cases::check_min_version();
    npm_cases::check_intersects();
    npm_cases::check_subset();
    npm_cases::check_outside();
    npm_cases::check_valid();
    npm_cases::check_compare_text();
    npm_cases::check_identifiers();
    npm_cases::check_cmp();
    npm_cases::check_comparators();
    npm_cases::check_simplify();
    print("all tests passed");
    return 0;
}
