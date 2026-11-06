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
    // But a non-numeric part may, and so may the build metadata.
    let v9, ok9 = semver::parse("1.2.3-alpha.01");
    assert(ok9);
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

fn main() {
    test_parse();
    test_parse_faults();
    test_order();
    test_format();
    print("all tests passed");
    return 0;
}
