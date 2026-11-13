// The outside, gtr and ltr calls: whether a version lies beyond a range.
//
namespace semver;

import std;

// outside tells whether the version is above every version of the range
// (hilo is ">") or below every version of it (hilo is "<"). It is the
// outside of npm. A bad range or another hilo gives false.
fn outside(v: Version, range: const u8[:], hilo: const u8[:]) -> bool {
    return outside_match(v, range, hilo, false);
}

// outside_match is outside with the flag of the pre-release rule.
fn outside_match(v: Version, range: const u8[:], hilo: const u8[:], inc: bool) -> bool {
    var up = true;
    if hilo == "<" { up = false; } else if hilo != ">" { return false; }
    var norm: u8[>..] = [];
    var comps: Comparator[>..] = [];
    var ends: i64[>..] = [];
    if !parse_range(norm, comps, ends, range, inc) { return false; }
    if range_ok(v, comps, ends, inc) { return false; }
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
    return outside_match(v, range, ">", false);
}

// gtr_o is gtr with the options.
fn gtr_o(v: Version, range: const u8[:], o: RangeOpts) -> bool {
    return outside_match(v, range, ">", o.include_prerelease);
}

// ltr_o is ltr with the options.
fn ltr_o(v: Version, range: const u8[:], o: RangeOpts) -> bool {
    return outside_match(v, range, "<", o.include_prerelease);
}

// to_comparators writes the sets of the range into the list. The `||` in
// the range starts a new list. It gives false for a bad range. The
// texts of the parts point into norm, so norm must outlive the list.
fn to_comparators(norm: u8[>..]&, parts: const u8[:][>..]&, ends: i64[>..]&, range: const u8[:]) -> bool {
    return to_comparators_o(norm, parts, ends, range, RangeOpts { .. });
}

// to_comparators_o is to_comparators with the options.
fn to_comparators_o(norm: u8[>..]&, parts: const u8[:][>..]&, ends: i64[>..]&, range: const u8[:], o: RangeOpts) -> bool {
    if range.len > MAX_RANGE_BYTES { return false; }
    if !normalize(norm, range, o.include_prerelease) { return false; }
    let sets = split(norm[..], "||");
    var i: i64 = 0;
    while i < sets.len {
        let set = sets[i];
        for w in words(set) { parts.push(w); }
        ends.push(parts.len);
        i += 1;
    }
    return true;
}

// simplify_range writes the range text of npm into out. It keeps the
// versions that the range names. It gives false for a bad range.
fn simplify_range(out: u8[>..]&, versions: const u8[:][:], range: const u8[:]) -> bool {
    return simplify_range_o(out, versions, range, RangeOpts { .. });
}

// simplify_range_o is simplify_range with the options.
fn simplify_range_o(out: u8[>..]&, versions: const u8[:][:], range: const u8[:], o: RangeOpts) -> bool {
    // The range is read once. The sets hold the strict comparators.
    if range.len > MAX_RANGE_BYTES { return false; }
    var norm: u8[>..] = [];
    if !normalize(norm, range, o.include_prerelease) { return false; }
    let sets = split(norm[..], "||");
    // The versions come in order, as npm sorts them.
    var order: i64[>..] = [];
    sort(order, versions);
    // The runs of the versions that the range keeps. A run holds the
    // first and the last version of it. The last run has no last
    // version, and its end stands for none.
    var first: i64 = -1;
    var prev: i64 = -1;
    var wrote = false;
    var i: i64 = 0;
    while i < order.len {
        let text = versions[order[i]];
        let v, ok = parse(text);
        if !ok { return false; }
        var hit = false;
        for set in sets {
            if set_matches(v, set, o.include_prerelease) { hit = true; }
        }
        if hit {
            if first < 0 { first = order[i]; }
            prev = order[i];
        } else {
            if first >= 0 {
                run_text(out, versions[first], versions[prev], first == order[0], wrote);
                wrote = true;
                first = -1;
                prev = -1;
            }
        }
        i += 1;
    }
    if first >= 0 {
        // The last run has no last version. npm gives it none.
        run_text(out, versions[first], "", first == order[0], wrote);
    }
    // npm keeps the shorter of the two texts.
    if out.len >= range.len {
        out.clear();
        out.append(range);
    }
    return true;
}

// run_text gives the text of one run of the versions. The last version
// is empty when the run reaches the end of the list.
fn run_text(out: u8[>..]&, min: const u8[:], max: const u8[:], at_lowest: bool, wrote: bool) {
    if wrote { out.append(" || "); }
    if max.len == 0 {
        if at_lowest { out.append("*"); }
        else { out.append(">="); out.append(min); }
        return;
    }
    if min == max { out.append(min); return; }
    if at_lowest {
        out.append("<=");
        out.append(max);
        return;
    }
    out.append(min);
    out.append(" - ");
    out.append(max);
}

// ltr tells whether the version is below every version of the range.
fn ltr(v: Version, range: const u8[:]) -> bool {
    return outside_match(v, range, "<", false);
}

// outside_o is outside with the options.
fn outside_o(v: Version, range: const u8[:], hilo: const u8[:], o: RangeOpts) -> bool {
    return outside_match(v, range, hilo, o.include_prerelease);
}
