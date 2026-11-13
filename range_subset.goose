// The subset call: whether every version of one range lies in another.
//
namespace semver;

import std;

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
fn simple_subset(s: Comparator[>..]&, d: Comparator[>..]&, inc: bool) -> i32 {
    var min_comp = make_comp(OP_GTE, zero_version());
    if s.len == 1 && s[0].op == OP_ANY {
        if d.len == 1 && d[0].op == OP_ANY { return 1; }
        // With the flag the lowest bound is ">=0.0.0-0".
        if inc { min_comp = make_comp(OP_GTE, Version { major: 0, minor: 0, patch: 0, pre: "0", build: "" }); }
        s.clear();
        s.push(min_comp);
    }
    if d.len == 1 && d[0].op == OP_ANY {
        if inc { return 1; }
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
        if has_hi && !one_matches(eq_v, hi_c, inc) { return 2; }
        if has_lo && !one_matches(eq_v, lo_c, inc) { return 2; }
        for c in d {
            if !one_matches(eq_v, c, inc) { return 0; }
        }
        return 1;
    }

    var has_dom_gt = false;
    var has_dom_lt = false;
    // A bound with a pre-release needs a comparator of its tuple with a
    // pre-release in the other set.
    // The flag turns the need off.
    var need_gt = !inc && has_hi && hi_c.v.pre.len > 0;
    var need_lt = !inc && has_lo && lo_c.v.pre.len > 0;
    // The exception: <1.2.3-0 is the same as <1.2.3.
    if need_lt && lo_c.v.pre == "0" && lo_c.op == OP_LT { need_lt = false; }

    for c in d {
        if is_up(c.op) { has_dom_gt = true; }
        if is_down(c.op) { has_dom_lt = true; }
        if has_hi {
            if need_gt && c.v.pre.len > 0 && same_tuple(c.v, hi_c.v) { need_gt = false; }
            if is_up(c.op) {
                if gt_beaten(hi_c, c) { return 0; }
            } else if hi_c.op == OP_GTE && !one_matches(hi_c.v, c, inc) {
                return 0;
            }
        }
        if has_lo {
            if need_lt && c.v.pre.len > 0 && same_tuple(c.v, lo_c.v) { need_lt = false; }
            if is_down(c.op) {
                if lt_beaten(lo_c, c) { return 0; }
            } else if lo_c.op == OP_LTE && !one_matches(lo_c.v, c, inc) {
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
    return subset_o(sub, dom, RangeOpts { .. });
}

// subset_o is subset with the options.
fn subset_o(sub: const u8[:], dom: const u8[:], o: RangeOpts) -> bool {
    let inc = o.include_prerelease;
    if sub == dom { return true; }
    var ns: u8[>..] = [];
    var cs: Comparator[>..] = [];
    var es: i64[>..] = [];
    var nd: u8[>..] = [];
    var cd: Comparator[>..] = [];
    var ed: i64[>..] = [];
    if !parse_range(ns, cs, es, sub, inc) { return false; }
    if !parse_range(nd, cd, ed, dom, inc) { return false; }
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
            let r = simple_subset(s, d, inc);
            if r != 2 { saw_non_null = true; }
            if r == 1 { matched = true; }
            j += 1;
        }
        if !matched && saw_non_null { return false; }
        i += 1;
    }
    return true;
}
