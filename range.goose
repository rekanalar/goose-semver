// Lists and ranges for the semver package.
//
// This file holds the calls that scan a list of versions, order a list,
// and compare two ranges. They follow the npm package semver 7.6.1:
// maxSatisfying, minSatisfying, sort, rsort, compareBuild, minVersion,
// intersects, subset, outside, gtr and ltr.
//
// A list is a slice of version texts. A call that selects or sorts gives
// places in the list, so no result holds a slice of a text.
//
// A range is read with normalize. Each "||" alternative becomes a set of
// comparators. A bad range, a range above the limits, or a bad version
// never aborts a call. The call gives the neutral result: -1, false, or
// no version.
namespace semver;

import std;

// The most "||" alternatives that a range may hold. The compare of two
// ranges tries every pair of alternatives, so the limit bounds its time.
const MAX_ALTERNATIVES: i64 = 1024;

// The most bytes that a range may hold. A longer range counts as bad.
// The length is checked before the range is read.
const MAX_RANGE_BYTES: i64 = 16384;

// The operators of a comparator. OP_ANY matches every release. OP_NONE
// stands for a comparator that is not set.
const OP_EQ: i32 = 0;
const OP_GT: i32 = 1;
const OP_GTE: i32 = 2;
const OP_LT: i32 = 3;
const OP_LTE: i32 = 4;
const OP_ANY: i32 = 5;
const OP_NONE: i32 = 6;

// Comparator is one test of a version: an operator and a version.
struct Comparator {
    op: i32,
    v: Version,
}

fn zero_version() -> Version {
    return Version { major: 0, minor: 0, patch: 0, pre: "", build: "" };
}

fn make_comp(op: i32, v: Version) -> Comparator {
    return Comparator { op: op, v: v };
}

// op_code gives the code of the operator text of a strict comparator.
fn op_code(text: const u8[:]) -> i32 {
    if text == ">" { return OP_GT; }
    if text == ">=" { return OP_GTE; }
    if text == "<" { return OP_LT; }
    if text == "<=" { return OP_LTE; }
    return OP_EQ;
}

fn is_up(op: i32) -> bool {
    return op == OP_GT || op == OP_GTE;
}

fn is_down(op: i32) -> bool {
    return op == OP_LT || op == OP_LTE;
}

// same_tuple tells whether two versions hold the same three numbers.
fn same_tuple(a: Version, b: Version) -> bool {
    return a.major == b.major && a.minor == b.minor && a.patch == b.patch;
}

// ---- the comparison helpers ---------------------------------------------

// gt tells whether a is higher than b.
fn gt(a: Version, b: Version) -> bool { return compare(a, b) > 0; }

// gte tells whether a is higher than b or equal to it.
fn gte(a: Version, b: Version) -> bool { return compare(a, b) >= 0; }

// lt tells whether a is lower than b.
fn lt(a: Version, b: Version) -> bool { return compare(a, b) < 0; }

// lte tells whether a is lower than b or equal to it.
fn lte(a: Version, b: Version) -> bool { return compare(a, b) <= 0; }

// eq tells whether a and b hold the same precedence. The build part takes
// no part in the order.
fn eq(a: Version, b: Version) -> bool { return compare(a, b) == 0; }

// neq tells whether a and b hold different precedence.
fn neq(a: Version, b: Version) -> bool { return compare(a, b) != 0; }

// compare_numbers compares two texts of digits by value. A leading zero
// does not count.
fn compare_numbers(a: const u8[:], b: const u8[:]) -> i64 {
    var x = a;
    var y = b;
    while x.len > 0 && x[0] == '0' { x = x[1..]; }
    while y.len > 0 && y[0] == '0' { y = y[1..]; }
    if x.len != y.len { return if x.len < y.len { -1 } else { 1 }; }
    return compare_bytes(x, y);
}

// compare_identifiers in semver.goose gives the order of two parts. A
// number comes before a text, and two numbers compare by value. The
// build part and the pre-release use the same rule, as npm does.

// compare_build_part compares the build parts of two versions, as npm
// compareBuild does. A result of zero ends the compare, even when the
// texts differ, for example 001 and 1.
fn compare_build_part(a: const u8[:], b: const u8[:]) -> i64 {
    var ai: i64 = 0;
    var bi: i64 = 0;
    loop {
        let a_done = ai >= a.len;
        let b_done = bi >= b.len;
        if a_done && b_done { return 0; }
        if b_done { return 1; }
        if a_done { return -1; }
        let ae = part_end(a, ai);
        let be = part_end(b, bi);
        let ap = a[ai..ae];
        let bp = b[bi..be];
        if ap != bp { return compare_identifiers(ap, bp); }
        ai = ae + 1;
        bi = be + 1;
    }
}

// compare_build puts a before b by precedence, and then by the build part.
// It gives a negative number when a comes first, a positive one when b
// comes first, and zero for an equal pair.
fn compare_build(a: Version, b: Version) -> i64 {
    let c = compare(a, b);
    if c != 0 { return if c < 0 { -1 } else { 1 }; }
    return compare_build_part(a.build, b.build);
}

// ---- sort ----------------------------------------------------------------

// sort_places writes the places of the list into order. A text that is not
// a version goes last, in the order of the input. The sort is stable.
fn sort_places(order: i64[>..]&, versions: const u8[:][:], desc: bool) {
    order.clear();
    var vs: Version[>..] = [];
    var good: i64[>..] = [];
    var bad: i64[>..] = [];
    var i: i64 = 0;
    while i < versions.len {
        let v, ok = parse(versions[i]);
        vs.push(v);
        if ok { good.push(i); } else { bad.push(i); }
        i += 1;
    }
    // A bottom-up merge sort. The width of the runs doubles each round.
    var src: i64[>..] = [];
    var dst: i64[>..] = [];
    for g in good { src.push(g); dst.push(g); }
    let n: i64 = src.len;
    var width: i64 = 1;
    while width < n {
        var lo: i64 = 0;
        while lo < n {
            let mid = if lo + width < n { lo + width } else { n };
            let hi = if lo + 2 * width < n { lo + 2 * width } else { n };
            var l = lo;
            var r = mid;
            var k = lo;
            while l < mid && r < hi {
                let c = compare_build(vs[src[l]], vs[src[r]]);
                let take_left = if desc { c >= 0 } else { c <= 0 };
                if take_left { dst[k] = src[l]; l += 1; } else { dst[k] = src[r]; r += 1; }
                k += 1;
            }
            while l < mid { dst[k] = src[l]; l += 1; k += 1; }
            while r < hi { dst[k] = src[r]; r += 1; k += 1; }
            lo += 2 * width;
        }
        // The result of the round becomes the source of the next one.
        var j: i64 = 0;
        while j < n { src[j] = dst[j]; j += 1; }
        width *= 2;
    }
    for g in src { order.push(g); }
    for b in bad { order.push(b); }
}

// sort writes the places of the versions in ascending order into order.
// It orders by precedence and then by the build part, as npm sort does.
fn sort(order: i64[>..]&, versions: const u8[:][:]) {
    sort_places(order, versions, false);
}

// rsort writes the places of the versions in descending order into order.
fn rsort(order: i64[>..]&, versions: const u8[:][:]) {
    sort_places(order, versions, true);
}

// ---- reading a range -----------------------------------------------------

// add_set reads one set of strict comparators into comps.
fn add_set(comps: Comparator[>..]&, set: const u8[:]) -> bool {
    let toks = words(set);
    if toks.len == 0 {
        comps.push(make_comp(OP_ANY, zero_version()));
        return true;
    }
    for tok in toks {
        let _, o = split_op(tok);
        let v, ok = parse(tok[o.len..]);
        if !ok { return false; }
        comps.push(make_comp(op_code(o), v));
    }
    return true;
}

// parse_range reads a range into sets of comparators. The text of the
// versions lives in norm, so norm must outlive comps. The set i holds the
// comparators from ends[i - 1] up to ends[i]. It gives false for a bad
// range, a range above MAX_RANGE_BYTES, or more than MAX_ALTERNATIVES sets.
//
// The sets follow npm Range; normalize drops the null sets.
// A range that matches every release is one set with one OP_ANY. The flag
// inc reads the range as npm reads it with includePrerelease.
fn parse_range(norm: u8[>..]&, comps: Comparator[>..]&, ends: i64[>..]&, range: const u8[:], inc: bool) -> bool {
    if range.len > MAX_RANGE_BYTES { return false; }
    if !normalize(norm, range, inc) { return false; }
    if norm.len == 0 {
        comps.push(make_comp(OP_ANY, zero_version()));
        ends.push(comps.len);
        return true;
    }
    let sets = split(norm[..], "||");
    if sets.len > MAX_ALTERNATIVES { return false; }
    for set in sets {
        if !add_set(comps, set) { return false; }
        ends.push(comps.len);
    }
    return true;
}

fn set_start(ends: i64[>..]&, i: i64) -> i64 {
    if i == 0 { return 0; }
    return ends[i - 1];
}

// ---- testing a version ---------------------------------------------------

// comp_hit tells whether the version passes the test of one comparator.
fn comp_hit(v: Version, c: Comparator) -> bool {
    if c.op == OP_ANY { return true; }
    let r = compare(v, c.v);
    if c.op == OP_EQ { return r == 0; }
    if c.op == OP_GT { return r > 0; }
    if c.op == OP_GTE { return r >= 0; }
    if c.op == OP_LT { return r < 0; }
    return r <= 0;
}

// names_tuple tells whether the comparator carries a pre-release of the
// tuple of the version.
fn names_tuple(c: Comparator, v: Version) -> bool {
    return c.op != OP_ANY && c.v.pre.len > 0 && same_tuple(c.v, v);
}

// one_matches tells whether the version fits a range of one comparator.
fn one_matches(v: Version, c: Comparator, inc: bool) -> bool {
    if !comp_hit(v, c) { return false; }
    if v.pre.len > 0 && !inc { return names_tuple(c, v); }
    return true;
}

// set_ok tells whether the version fits the set from lo up to hi. A
// version with a pre-release needs a comparator of its tuple with a
// pre-release.
fn set_ok(v: Version, comps: Comparator[>..]&, lo: i64, hi: i64, inc: bool) -> bool {
    var pre_ok = false;
    var i = lo;
    while i < hi {
        if !comp_hit(v, comps[i]) { return false; }
        if names_tuple(comps[i], v) { pre_ok = true; }
        i += 1;
    }
    if v.pre.len > 0 && !inc { return pre_ok; }
    return true;
}

// range_ok tells whether the version fits one set of the range.
fn range_ok(v: Version, comps: Comparator[>..]&, ends: i64[>..]&, inc: bool) -> bool {
    var i: i64 = 0;
    while i < ends.len {
        if set_ok(v, comps, set_start(ends, i), ends[i], inc) { return true; }
        i += 1;
    }
    return false;
}

// ---- selection -----------------------------------------------------------

// select gives the place of the highest or the lowest version of the list
// that the range accepts, or -1. An equal version does not replace an
// earlier one, as in npm.
fn select(versions: const u8[:][:], range: const u8[:], want_max: bool, inc: bool) -> i64 {
    var norm: u8[>..] = [];
    var comps: Comparator[>..] = [];
    var ends: i64[>..] = [];
    if !parse_range(norm, comps, ends, range, inc) { return -1; }
    var best: i64 = -1;
    var best_v = zero_version();
    var i: i64 = 0;
    while i < versions.len {
        let v, ok = parse(versions[i]);
        if ok && range_ok(v, comps, ends, inc) {
            if best < 0 {
                best = i;
                best_v = v;
            } else {
                let c = compare(best_v, v);
                if (want_max && c < 0) || (!want_max && c > 0) {
                    best = i;
                    best_v = v;
                }
            }
        }
        i += 1;
    }
    return best;
}

// max_satisfying gives the place of the highest version of the list that
// the range accepts, or -1.
fn max_satisfying(versions: const u8[:][:], range: const u8[:]) -> i64 {
    return select(versions, range, true, false);
}

// max_satisfying_o is max_satisfying with the options. With the flag
// the pre-release rule of the range goes off, as npm gives.
fn max_satisfying_o(versions: const u8[:][:], range: const u8[:], o: RangeOpts) -> i64 {
    return select(versions, range, true, o.include_prerelease);
}

// min_satisfying gives the place of the lowest version of the list that
// the range accepts, or -1.
fn min_satisfying(versions: const u8[:][:], range: const u8[:]) -> i64 {
    return select(versions, range, false, false);
}

// min_satisfying_o is min_satisfying with the options.
fn min_satisfying_o(versions: const u8[:][:], range: const u8[:], o: RangeOpts) -> i64 {
    return select(versions, range, false, o.include_prerelease);
}

// ---- min_version ---------------------------------------------------------

// write_core writes a version without its build part.
fn write_core(out: u8[>..]&, v: Version) {
    format(out, v.major);
    out.push('.');
    format(out, v.minor);
    out.push('.');
    format(out, v.patch);
    if v.pre.len > 0 {
        out.push('-');
        out.append(v.pre);
    }
}

// min_version writes the lowest version that the range accepts into out. It
// gives false, with out untouched, when no version fits.
fn min_version(out: u8[>..]&, range: const u8[:]) -> bool {
    return min_version_o(out, range, RangeOpts { .. });
}

// min_version_o is min_version with the options.
fn min_version_o(out: u8[>..]&, range: const u8[:], o: RangeOpts) -> bool {
    let inc = o.include_prerelease;
    var norm: u8[>..] = [];
    var comps: Comparator[>..] = [];
    var ends: i64[>..] = [];
    if !parse_range(norm, comps, ends, range, inc) { return false; }
    let zero = zero_version();
    if range_ok(zero, comps, ends, inc) {
        write_core(out, zero);
        return true;
    }
    let zero_pre = Version { major: 0, minor: 0, patch: 0, pre: "0", build: "" };
    if range_ok(zero_pre, comps, ends, inc) {
        write_core(out, zero_pre);
        return true;
    }
    // The lowest bound of each set is a candidate. The lowest candidate
    // that the range accepts is the answer. A candidate is a comparator
    // that stands by its index.
    var best: i64 = -1;
    var s: i64 = 0;
    while s < ends.len {
        var set_best: i64 = -1;
        var i = set_start(ends, s);
        while i < ends[s] {
            let op = comps[i].op;
            if op == OP_GT || op == OP_GTE || op == OP_EQ {
                if set_best < 0 || cand_cmp(comps[i], comps[set_best]) > 0 { set_best = i; }
            }
            i += 1;
        }
        if set_best >= 0 && (best < 0 || cand_cmp(comps[best], comps[set_best]) > 0) {
            best = set_best;
        }
        s += 1;
    }
    if best < 0 { return false; }
    var text: u8[>..] = [];
    cand_text(text, comps[best]);
    let mv, ok = parse(text[..]);
    if !ok || !range_ok(mv, comps, ends, inc) { return false; }
    out.append(text[..]);
    return true;
}

// cand_text writes the lowest version that a lower bound allows. A ">"
// bound allows the next patch number, or the same pre-release with a
// zero part added.
fn cand_text(out: u8[>..]&, c: Comparator) {
    if c.op != OP_GT {
        write_core(out, c.v);
        return;
    }
    if c.v.pre.len == 0 {
        format(out, c.v.major);
        out.push('.');
        format(out, c.v.minor);
        out.push('.');
        let next: i64 = c.v.patch;
        format(out, next + 1);
    } else {
        write_core(out, c.v);
        out.append(".0");
    }
}

// cand_cmp compares the lowest versions that two lower bounds allow.
fn cand_cmp(a: Comparator, b: Comparator) -> i64 {
    var ta: u8[>..] = [];
    var tb: u8[>..] = [];
    cand_text(ta, a);
    cand_text(tb, b);
    let va, _ = parse(ta[..]);
    let vb, _ = parse(tb[..]);
    return compare(va, vb);
}

// ---- intersects ----------------------------------------------------------

// comp_intersects tells whether two comparators can hold for one version.
// It is the Comparator.intersects of npm, including its order of tests.
fn comp_intersects(a: Comparator, b: Comparator, inc: bool) -> bool {
    if a.op == OP_ANY { return true; }
    if a.op == OP_EQ { return one_matches(a.v, b, inc); }
    if b.op == OP_ANY { return true; }
    if b.op == OP_EQ { return one_matches(b.v, a, inc); }
    // Nothing is lower than 0.0.0, so a "<" bound there holds no version.
    // With the flag only "<0.0.0-0" counts, as in npm.
    let zero_a = a.op == OP_LT && a.v.major == 0 && a.v.minor == 0 && a.v.patch == 0 && (!inc || a.v.pre == "0");
    let zero_b = b.op == OP_LT && b.v.major == 0 && b.v.minor == 0 && b.v.patch == 0 && (!inc || b.v.pre == "0");
    if zero_a || zero_b { return false; }
    let a_up = is_up(a.op);
    let b_up = is_up(b.op);
    if a_up && b_up { return true; }
    if !a_up && !b_up { return true; }
    let r = compare(a.v, b.v);
    let a_incl = a.op == OP_GTE || a.op == OP_LTE;
    let b_incl = b.op == OP_GTE || b.op == OP_LTE;
    if r == 0 && a_incl && b_incl { return true; }
    if r < 0 && a_up && !b_up { return true; }
    if r > 0 && !a_up && b_up { return true; }
    return false;
}

// set_satisfiable tells whether one version can fit all comparators of a
// set. It is the isSatisfiable of npm: the last comparator is tested
// against the others, then the one before it, and so on.
fn set_satisfiable(comps: Comparator[>..]&, lo: i64, hi: i64, inc: bool) -> bool {
    var top = hi - 1;
    while top > lo {
        var j = lo;
        while j < top {
            if !comp_intersects(comps[top], comps[j], inc) { return false; }
            j += 1;
        }
        top -= 1;
    }
    return true;
}

// intersects tells whether one version can fit both ranges. A bad range
// gives false.
fn intersects(a: const u8[:], b: const u8[:]) -> bool {
    return intersects_o(a, b, RangeOpts { .. });
}

// intersects_o is intersects with the options.
fn intersects_o(a: const u8[:], b: const u8[:], o: RangeOpts) -> bool {
    let inc = o.include_prerelease;
    var na: u8[>..] = [];
    var ca: Comparator[>..] = [];
    var ea: i64[>..] = [];
    var nb: u8[>..] = [];
    var cb: Comparator[>..] = [];
    var eb: i64[>..] = [];
    if !parse_range(na, ca, ea, a, inc) { return false; }
    if !parse_range(nb, cb, eb, b, inc) { return false; }
    var sat_b: bool[>..] = [];
    var j: i64 = 0;
    while j < eb.len {
        sat_b.push(set_satisfiable(cb, set_start(eb, j), eb[j], inc));
        j += 1;
    }
    var i: i64 = 0;
    while i < ea.len {
        let alo = set_start(ea, i);
        if set_satisfiable(ca, alo, ea[i], inc) {
            j = 0;
            while j < eb.len {
                if sat_b[j] {
                    var all = true;
                    var x = alo;
                    while x < ea[i] && all {
                        var y = set_start(eb, j);
                        while y < eb[j] && all {
                            if !comp_intersects(ca[x], cb[y], inc) { all = false; }
                            y += 1;
                        }
                        x += 1;
                    }
                    if all { return true; }
                }
                j += 1;
            }
        }
        i += 1;
    }
    return false;
}
