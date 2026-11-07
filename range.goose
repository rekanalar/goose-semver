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
    return compare_text(x, y);
}

// compare_ident compares two identifiers of a build part. A number comes
// before a text. Two numbers compare by value.
fn compare_ident(a: const u8[:], b: const u8[:]) -> i64 {
    let an = is_numeric(a);
    let bn = is_numeric(b);
    if an && bn { return compare_numbers(a, b); }
    if an { return -1; }
    if bn { return 1; }
    return compare_text(a, b);
}

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
        if ap != bp { return compare_ident(ap, bp); }
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

// is_null_text tells whether a set is the null set.
fn is_null_text(set: const u8[:]) -> bool {
    let w = words(set);
    return w.len == 1 && w[0] == "<0.0.0-0";
}

// add_set reads one set of strict comparators into comps. It drops a
// comparator that repeats an earlier one of the same set.
fn add_set(comps: Comparator[>..]&, set: const u8[:]) -> bool {
    let first: i64 = comps.len;
    let toks = words(set);
    if toks.len == 0 {
        comps.push(make_comp(OP_ANY, zero_version()));
        return true;
    }
    for tok in toks {
        let _, o = split_op(tok);
        let v, ok = parse(tok[o.len..]);
        if !ok { return false; }
        let code = op_code(o);
        var dup = false;
        var i: i64 = first;
        while i < comps.len {
            if comps[i].op == code && compare(comps[i].v, v) == 0 { dup = true; }
            i += 1;
        }
        if !dup { comps.push(make_comp(code, v)); }
    }
    return true;
}

// parse_range reads a range into sets of comparators. The text of the
// versions lives in norm, so norm must outlive comps. The set i holds the
// comparators from ends[i - 1] up to ends[i]. It gives false for a bad
// range, a range above MAX_RANGE_BYTES, or more than MAX_ALTERNATIVES sets.
//
// The sets follow npm Range. A null set is dropped when another set stays.
// A range that matches every release is one set with one OP_ANY.
fn parse_range(norm: u8[>..]&, comps: Comparator[>..]&, ends: i64[>..]&, range: const u8[:]) -> bool {
    if range.len > MAX_RANGE_BYTES { return false; }
    if !normalize(norm, range) { return false; }
    if norm.len == 0 {
        comps.push(make_comp(OP_ANY, zero_version()));
        ends.push(comps.len);
        return true;
    }
    let sets = split(norm[..], "||");
    if sets.len > MAX_ALTERNATIVES { return false; }
    var live: i64 = 0;
    for s in sets { if !is_null_text(s) { live += 1; } }
    var i: i64 = 0;
    while i < sets.len {
        let null_set = is_null_text(sets[i]);
        // With more than one set, the null sets go. When all are null, the
        // first stays.
        var skip = false;
        if sets.len > 1 && null_set && live > 0 { skip = true; }
        if sets.len > 1 && live == 0 && i > 0 { skip = true; }
        if !skip {
            if !add_set(comps, sets[i]) { return false; }
            ends.push(comps.len);
        }
        i += 1;
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
fn one_matches(v: Version, c: Comparator) -> bool {
    if !comp_hit(v, c) { return false; }
    if v.pre.len > 0 { return names_tuple(c, v); }
    return true;
}

// set_ok tells whether the version fits the set from lo up to hi. A
// version with a pre-release needs a comparator of its tuple with a
// pre-release.
fn set_ok(v: Version, comps: Comparator[>..]&, lo: i64, hi: i64) -> bool {
    var pre_ok = false;
    var i = lo;
    while i < hi {
        if !comp_hit(v, comps[i]) { return false; }
        if names_tuple(comps[i], v) { pre_ok = true; }
        i += 1;
    }
    if v.pre.len > 0 { return pre_ok; }
    return true;
}

// range_ok tells whether the version fits one set of the range.
fn range_ok(v: Version, comps: Comparator[>..]&, ends: i64[>..]&) -> bool {
    var i: i64 = 0;
    while i < ends.len {
        if set_ok(v, comps, set_start(ends, i), ends[i]) { return true; }
        i += 1;
    }
    return false;
}

// ---- selection -----------------------------------------------------------

// select gives the place of the highest or the lowest version of the list
// that the range accepts, or -1. An equal version does not replace an
// earlier one, as in npm.
fn select(versions: const u8[:][:], range: const u8[:], want_max: bool) -> i64 {
    var norm: u8[>..] = [];
    var comps: Comparator[>..] = [];
    var ends: i64[>..] = [];
    if !parse_range(norm, comps, ends, range) { return -1; }
    var best: i64 = -1;
    var best_v = zero_version();
    var i: i64 = 0;
    while i < versions.len {
        let v, ok = parse(versions[i]);
        if ok && range_ok(v, comps, ends) {
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
    return select(versions, range, true);
}

// min_satisfying gives the place of the lowest version of the list that
// the range accepts, or -1.
fn min_satisfying(versions: const u8[:][:], range: const u8[:]) -> i64 {
    return select(versions, range, false);
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
    var norm: u8[>..] = [];
    var comps: Comparator[>..] = [];
    var ends: i64[>..] = [];
    if !parse_range(norm, comps, ends, range) { return false; }
    let zero = zero_version();
    if range_ok(zero, comps, ends) {
        write_core(out, zero);
        return true;
    }
    let zero_pre = Version { major: 0, minor: 0, patch: 0, pre: "0", build: "" };
    if range_ok(zero_pre, comps, ends) {
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
    if !ok || !range_ok(mv, comps, ends) { return false; }
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
fn comp_intersects(a: Comparator, b: Comparator) -> bool {
    if a.op == OP_ANY { return true; }
    if a.op == OP_EQ { return one_matches(a.v, b); }
    if b.op == OP_ANY { return true; }
    if b.op == OP_EQ { return one_matches(b.v, a); }
    // Nothing is lower than 0.0.0, so a "<" bound there holds no version.
    let zero_a = a.op == OP_LT && a.v.major == 0 && a.v.minor == 0 && a.v.patch == 0;
    let zero_b = b.op == OP_LT && b.v.major == 0 && b.v.minor == 0 && b.v.patch == 0;
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
fn set_satisfiable(comps: Comparator[>..]&, lo: i64, hi: i64) -> bool {
    var top = hi - 1;
    while top > lo {
        var j = lo;
        while j < top {
            if !comp_intersects(comps[top], comps[j]) { return false; }
            j += 1;
        }
        top -= 1;
    }
    return true;
}

// intersects tells whether one version can fit both ranges. A bad range
// gives false.
fn intersects(a: const u8[:], b: const u8[:]) -> bool {
    var na: u8[>..] = [];
    var ca: Comparator[>..] = [];
    var ea: i64[>..] = [];
    var nb: u8[>..] = [];
    var cb: Comparator[>..] = [];
    var eb: i64[>..] = [];
    if !parse_range(na, ca, ea, a) { return false; }
    if !parse_range(nb, cb, eb, b) { return false; }
    var sat_b: bool[>..] = [];
    var j: i64 = 0;
    while j < eb.len {
        sat_b.push(set_satisfiable(cb, set_start(eb, j), eb[j]));
        j += 1;
    }
    var i: i64 = 0;
    while i < ea.len {
        let alo = set_start(ea, i);
        if set_satisfiable(ca, alo, ea[i]) {
            j = 0;
            while j < eb.len {
                if sat_b[j] {
                    var all = true;
                    var x = alo;
                    while x < ea[i] && all {
                        var y = set_start(eb, j);
                        while y < eb[j] && all {
                            if !comp_intersects(ca[x], cb[y]) { all = false; }
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

// ---- subset --------------------------------------------------------------

// higher_gt gives the higher of two lower bounds. A ">=" is lower than a
// ">" of the same version. The first argument may be unset.
fn higher_gt(a: Comparator, b: Comparator) -> Comparator {
    if a.op == OP_NONE { return b; }
    let r = compare(a.v, b.v);
    if r > 0 { return a; }
    if r < 0 { return b; }
    if b.op == OP_GT && a.op == OP_GTE { return b; }
    return a;
}

// lower_lt gives the lower of two upper bounds. A "<=" is higher than a "<"
// of the same version. The first argument may be unset.
fn lower_lt(a: Comparator, b: Comparator) -> Comparator {
    if a.op == OP_NONE { return b; }
    let r = compare(a.v, b.v);
    if r < 0 { return a; }
    if r > 0 { return b; }
    if b.op == OP_LT && a.op == OP_LTE { return b; }
    return a;
}

// gt_beaten tells whether the lower bound c is strictly higher than g.
fn gt_beaten(g: Comparator, c: Comparator) -> bool {
    let r = compare(g.v, c.v);
    return r < 0 || (r == 0 && c.op == OP_GT && g.op == OP_GTE);
}

// lt_beaten tells whether the upper bound c is strictly lower than l.
fn lt_beaten(l: Comparator, c: Comparator) -> bool {
    let r = compare(l.v, c.v);
    return r > 0 || (r == 0 && c.op == OP_LT && l.op == OP_LTE);
}

// simple_subset tells whether the set s lies in the set d. It is the
// simpleSubset of npm. It gives 1 for yes, 0 for no, and 2 for the null set,
// which npm gives as null. The two lists are work buffers that the call
// fills.
fn simple_subset(s: Comparator[>..]&, d: Comparator[>..]&) -> i32 {
    let min_comp = make_comp(OP_GTE, zero_version());
    if s.len == 1 && s[0].op == OP_ANY {
        if d.len == 1 && d[0].op == OP_ANY { return 1; }
        s.clear();
        s.push(min_comp);
    }
    if d.len == 1 && d[0].op == OP_ANY {
        d.clear();
        d.push(min_comp);
    }

    var hi_c = make_comp(OP_NONE, zero_version());
    var lo_c = make_comp(OP_NONE, zero_version());
    var eq_count: i64 = 0;
    var eq_v = zero_version();
    for c in s {
        if is_up(c.op) {
            hi_c = higher_gt(hi_c, c);
        } else if is_down(c.op) {
            lo_c = lower_lt(lo_c, c);
        } else {
            eq_count += 1;
            eq_v = c.v;
        }
    }
    if eq_count > 1 { return 2; }

    let has_hi = hi_c.op != OP_NONE;
    let has_lo = lo_c.op != OP_NONE;
    // The compare of the two bounds. Any value but zero when one is unset.
    var gtlt: i64 = 1;
    if has_hi && has_lo {
        gtlt = compare(hi_c.v, lo_c.v);
        if gtlt > 0 { return 2; }
        if gtlt == 0 && (hi_c.op != OP_GTE || lo_c.op != OP_LTE) { return 2; }
    }

    if eq_count == 1 {
        if has_hi && !one_matches(eq_v, hi_c) { return 2; }
        if has_lo && !one_matches(eq_v, lo_c) { return 2; }
        for c in d {
            if !one_matches(eq_v, c) { return 0; }
        }
        return 1;
    }

    var has_dom_gt = false;
    var has_dom_lt = false;
    // A bound with a pre-release needs a comparator of its tuple with a
    // pre-release in the other set.
    var need_gt = has_hi && hi_c.v.pre.len > 0;
    var need_lt = has_lo && lo_c.v.pre.len > 0;
    // The exception: <1.2.3-0 is the same as <1.2.3.
    if need_lt && lo_c.v.pre == "0" && lo_c.op == OP_LT { need_lt = false; }

    for c in d {
        if is_up(c.op) { has_dom_gt = true; }
        if is_down(c.op) { has_dom_lt = true; }
        if has_hi {
            if need_gt && c.v.pre.len > 0 && same_tuple(c.v, hi_c.v) { need_gt = false; }
            if is_up(c.op) {
                if gt_beaten(hi_c, c) { return 0; }
            } else if hi_c.op == OP_GTE && !one_matches(hi_c.v, c) {
                return 0;
            }
        }
        if has_lo {
            if need_lt && c.v.pre.len > 0 && same_tuple(c.v, lo_c.v) { need_lt = false; }
            if is_down(c.op) {
                if lt_beaten(lo_c, c) { return 0; }
            } else if lo_c.op == OP_LTE && !one_matches(lo_c.v, c) {
                return 0;
            }
        }
        if c.op == OP_EQ && (has_hi || has_lo) && gtlt != 0 { return 0; }
    }

    if has_hi && has_dom_lt && !has_lo && gtlt != 0 { return 0; }
    if has_lo && has_dom_gt && !has_hi && gtlt != 0 { return 0; }
    if need_gt || need_lt { return 0; }
    return 1;
}

// subset tells whether every version that fits sub also fits dom. It is the
// subset of npm. A bad range gives false.
fn subset(sub: const u8[:], dom: const u8[:]) -> bool {
    if sub == dom { return true; }
    var ns: u8[>..] = [];
    var cs: Comparator[>..] = [];
    var es: i64[>..] = [];
    var nd: u8[>..] = [];
    var cd: Comparator[>..] = [];
    var ed: i64[>..] = [];
    if !parse_range(ns, cs, es, sub) { return false; }
    if !parse_range(nd, cd, ed, dom) { return false; }
    var s: Comparator[>..] = [];
    var d: Comparator[>..] = [];
    // Once a set that is not null is seen, a later null set no longer
    // counts as a subset. This is the rule of npm.
    var saw_non_null = false;
    var i: i64 = 0;
    while i < es.len {
        var matched = false;
        var j: i64 = 0;
        while j < ed.len && !matched {
            s.clear();
            d.clear();
            var x = set_start(es, i);
            while x < es[i] { s.push(cs[x]); x += 1; }
            var y = set_start(ed, j);
            while y < ed[j] { d.push(cd[y]); y += 1; }
            let r = simple_subset(s, d);
            if r != 2 { saw_non_null = true; }
            if r == 1 { matched = true; }
            j += 1;
        }
        if !matched && saw_non_null { return false; }
        i += 1;
    }
    return true;
}

// ---- outside, gtr and ltr ------------------------------------------------

// outside tells whether the version is above every version of the range
// (hilo is ">") or below every version of it (hilo is "<"). It is the
// outside of npm. A bad range or another hilo gives false.
fn outside(v: Version, range: const u8[:], hilo: const u8[:]) -> bool {
    var up = true;
    if hilo == "<" { up = false; } else if hilo != ">" { return false; }
    var norm: u8[>..] = [];
    var comps: Comparator[>..] = [];
    var ends: i64[>..] = [];
    if !parse_range(norm, comps, ends, range) { return false; }
    if range_ok(v, comps, ends) { return false; }
    let comp_op = if up { OP_GT } else { OP_LT };
    let ecomp_op = if up { OP_GTE } else { OP_LTE };
    var s: i64 = 0;
    while s < ends.len {
        var high = make_comp(OP_NONE, zero_version());
        var low = make_comp(OP_NONE, zero_version());
        var i = set_start(ends, s);
        while i < ends[s] {
            var c = comps[i];
            if c.op == OP_ANY { c = make_comp(OP_GTE, zero_version()); }
            if high.op == OP_NONE { high = c; }
            if low.op == OP_NONE { low = c; }
            let to_high = compare(c.v, high.v);
            let to_low = compare(c.v, low.v);
            // gtfn is gt for the ">" mode and lt for the "<" mode.
            let beats_high = if up { to_high > 0 } else { to_high < 0 };
            let beats_low = if up { to_low < 0 } else { to_low > 0 };
            if beats_high { high = c; } else if beats_low { low = c; }
            i += 1;
        }
        // The top bound has an operator that reaches the version.
        if high.op == comp_op || high.op == ecomp_op { return false; }
        let r = compare(v, low.v);
        // ltefn is lte for ">" and gte for "<". ltfn is lt for ">" and gt for "<".
        let le = if up { r <= 0 } else { r >= 0 };
        let strict = if up { r < 0 } else { r > 0 };
        if (low.op == OP_EQ || low.op == comp_op) && le {
            return false;
        } else if low.op == ecomp_op && strict {
            return false;
        }
        s += 1;
    }
    return true;
}

// gtr tells whether the version is above every version of the range.
fn gtr(v: Version, range: const u8[:]) -> bool {
    return outside(v, range, ">");
}

// ltr tells whether the version is below every version of the range.
fn ltr(v: Version, range: const u8[:]) -> bool {
    return outside(v, range, "<");
}
