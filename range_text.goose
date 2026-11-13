// Reading and normalizing the text of a range, and testing a version against it.
//
namespace semver;

import std;

// Part holds one version of a range text, where an x, a star or a missing
// number is -1.
struct Part {
    mj: i64,
    mn: i64,
    pt: i64,
    pre: const u8[:],
}

// xpart reads one number of a range, or an x or star as -1.
fn xpart(s: const u8[:]) -> i64, bool {
    if s == "x" || s == "X" || s == "*" { return -1, true; }
    if !num_form(s) { return 0, false; }
    let n, ok = parse_num(s);
    return n, ok;
}

// parse_partial reads a version of a range: leading 'v' and '=' marks,
// one to three numbers or x marks, and a pre-release. Build metadata is
// dropped.
fn parse_partial(s: const u8[:]) -> Part, bool {
    var r = Part { mj: -1, mn: -1, pt: -1, pre: "" };
    var t = s;
    while t.len > 0 && (t[0] == 'v' || t[0] == '=') { t = t[1..]; }
    let plus = find(t, "+");
    if plus >= 0 {
        if !build_form(t[plus + 1..]) { return r, false; }
        t = t[..plus];
    }
    var has_pre = false;
    let dash = find(t, "-");
    if dash >= 0 {
        let pre = t[dash + 1..];
        if pre.len == 0 || !pre_form(pre) { return r, false; }
        r.pre = pre;
        has_pre = true;
        t = t[..dash];
    }
    let parts = split(t, '.');
    if parts.len > 3 { return r, false; }
    if has_pre && parts.len < 3 { return r, false; }
    let a, oka = xpart(parts[0]);
    if !oka { return r, false; }
    var b: i64 = -1;
    var c: i64 = -1;
    if parts.len > 1 {
        let b2, okb = xpart(parts[1]);
        if !okb { return r, false; }
        b = b2;
    }
    if parts.len > 2 {
        let c2, okc = xpart(parts[2]);
        if !okc { return r, false; }
        c = c2;
    }
    // 1.x.3 and x.2 hold a number after an x. That is a fault.
    if (a < 0 && b >= 0) || (b < 0 && c >= 0) { return r, false; }
    r.mj = a;
    r.mn = b;
    r.pt = c;
    // The pre-release counts only after a full version.
    if c < 0 { r.pre = ""; }
    return r, true;
}

// split_op reads the operator at the front of s. It gives the kind (0
// compare, 1 caret, 2 tilde) and the operator text.
fn split_op(s: const u8[:]) -> i32, const u8[:] {
    if starts_with(s, "^") { return 1, "^"; }
    if starts_with(s, "~>") { return 2, "~>"; }
    if starts_with(s, "~") { return 2, "~"; }
    if starts_with(s, "<=") { return 0, "<="; }
    if starts_with(s, ">=") { return 0, ">="; }
    if starts_with(s, "<") { return 0, "<"; }
    if starts_with(s, ">") { return 0, ">"; }
    if starts_with(s, "=") { return 0, "="; }
    return 0, "";
}

// add writes one comparator into seg. The null set "<0.0.0-0" sets the
// flag instead. ">=0.0.0" matches all, so it is dropped; with the flag
// `inc` the same bound is ">=0.0.0-0". z adds the "-0" pre-release, the
// lowest one. A comparator that repeats one of seg is not written again.
fn add(seg: u8[>..]&, nullset: bool&, op: const u8[:], ma: i64, mi: i64, pa: i64, pre: const u8[:], z: bool, inc: bool) {
    let zero_pre = pre == "0" || (pre.len == 0 && z);
    let no_pre = pre.len == 0 && !z;
    if op == "<" && ma == 0 && mi == 0 && pa == 0 && zero_pre { nullset = true; return; }
    if op == ">=" && ma == 0 && mi == 0 && pa == 0 && (if inc { zero_pre } else { no_pre }) { return; }
    var one: u8[>..] = [];
    one.append(op);
    format(one, ma);
    one.push('.');
    format(one, mi);
    one.push('.');
    format(one, pa);
    if pre.len > 0 { one.push('-'); one.append(pre); } else if z { one.append("-0"); }
    for w in words(seg[..]) {
        if w == one[..] { return; }
    }
    if seg.len > 0 { seg.push(' '); }
    seg.append(one);
}

// norm_token turns one range token into comparators in seg. pfx holds an
// operator that stood apart from the token ("> 1.2.3"), or is empty. The
// flag inc moves the lower bounds of x-ranges and carets to "-0", as npm.
fn norm_token(seg: u8[>..]&, nullset: bool&, pfx: const u8[:], tok: const u8[:], inc: bool) -> bool {
    var rest = tok;
    var kind: i32 = 0;
    var op: const u8[:] = "";
    if pfx.len > 0 {
        let k, o = split_op(pfx);
        kind = k;
        op = o;
    } else {
        let k, o = split_op(tok);
        kind = k;
        op = o;
        rest = tok[o.len..];
    }
    if op == "=" { op = ""; }
    let p, ok = parse_partial(rest);
    if !ok { return false; }
    let x_major = p.mj < 0;
    let x_minor = p.mn < 0;
    let x_patch = p.pt < 0;
    if x_major {
        // * matches all. > * and < * match nothing.
        if kind == 0 && (op == ">" || op == "<") { nullset = true; }
        return true;
    }
    if kind == 2 {
        // Tilde: the same minor, or the same major when no minor is given.
        // The flag changes nothing here.
        if x_minor {
            add(seg, nullset, ">=", p.mj, 0, 0, "", false, inc);
            add(seg, nullset, "<", p.mj + 1, 0, 0, "", true, inc);
        } else if x_patch {
            add(seg, nullset, ">=", p.mj, p.mn, 0, "", false, inc);
            add(seg, nullset, "<", p.mj, p.mn + 1, 0, "", true, inc);
        } else {
            add(seg, nullset, ">=", p.mj, p.mn, p.pt, p.pre, false, inc);
            add(seg, nullset, "<", p.mj, p.mn + 1, 0, "", true, inc);
        }
        return true;
    }
    if kind == 1 {
        // Caret: nothing left of the first non-zero number may change. The
        // flag adds "-0" to the lower bound, except for a major above zero
        // with a full version, and except when a pre-release is given.
        if x_minor {
            add(seg, nullset, ">=", p.mj, 0, 0, "", inc, inc);
            add(seg, nullset, "<", p.mj + 1, 0, 0, "", true, inc);
        } else if x_patch {
            add(seg, nullset, ">=", p.mj, p.mn, 0, "", inc, inc);
            if p.mj == 0 {
                add(seg, nullset, "<", 0, p.mn + 1, 0, "", true, inc);
            } else {
                add(seg, nullset, "<", p.mj + 1, 0, 0, "", true, inc);
            }
        } else {
            add(seg, nullset, ">=", p.mj, p.mn, p.pt, p.pre, inc && p.mj == 0, inc);
            if p.mj > 0 {
                add(seg, nullset, "<", p.mj + 1, 0, 0, "", true, inc);
            } else if p.mn > 0 {
                add(seg, nullset, "<", 0, p.mn + 1, 0, "", true, inc);
            } else {
                add(seg, nullset, "<", 0, 0, p.pt + 1, "", true, inc);
            }
        }
        return true;
    }
    // A plain comparator or an x-range.
    if op.len > 0 && x_patch {
        var o = op;
        var ma = p.mj;
        var mi: i64 = if x_minor { 0 } else { p.mn };
        if op == ">" {
            o = ">=";
            if x_minor { ma += 1; mi = 0; } else { mi += 1; }
        } else if op == "<=" {
            o = "<";
            if x_minor { ma += 1; } else { mi += 1; }
        }
        add(seg, nullset, o, ma, mi, 0, "", o == "<" || inc, inc);
    } else if x_minor {
        add(seg, nullset, ">=", p.mj, 0, 0, "", inc, inc);
        add(seg, nullset, "<", p.mj + 1, 0, 0, "", true, inc);
    } else if x_patch {
        add(seg, nullset, ">=", p.mj, p.mn, 0, "", inc, inc);
        add(seg, nullset, "<", p.mj, p.mn + 1, 0, "", true, inc);
    } else {
        add(seg, nullset, op, p.mj, p.mn, p.pt, p.pre, false, inc);
    }
    return true;
}

// norm_set turns one "||" alternative into comparators in seg.
fn norm_set(set: const u8[:], seg: u8[>..]&, nullset: bool&, inc: bool) -> bool {
    let toks = words(set);
    if toks.len == 3 && toks[1] == "-" {
        // A hyphen range: both ends are x-range versions. The flag moves
        // the low end to "-0" and a full high end to "<next patch-0".
        let a, oka = parse_partial(toks[0]);
        let b, okb = parse_partial(toks[2]);
        if !oka || !okb { return false; }
        if a.mj < 0 {
        } else if a.mn < 0 {
            add(seg, nullset, ">=", a.mj, 0, 0, "", inc, inc);
        } else if a.pt < 0 {
            add(seg, nullset, ">=", a.mj, a.mn, 0, "", inc, inc);
        } else {
            add(seg, nullset, ">=", a.mj, a.mn, a.pt, a.pre, inc, inc);
        }
        if b.mj < 0 {
        } else if b.mn < 0 {
            add(seg, nullset, "<", b.mj + 1, 0, 0, "", true, inc);
        } else if b.pt < 0 {
            add(seg, nullset, "<", b.mj, b.mn + 1, 0, "", true, inc);
        } else if b.pre.len == 0 && inc {
            add(seg, nullset, "<", b.mj, b.mn, b.pt + 1, "", true, inc);
        } else {
            add(seg, nullset, "<=", b.mj, b.mn, b.pt, b.pre, false, inc);
        }
        return true;
    }
    var i = 0;
    while i < toks.len {
        let t = toks[i];
        let _, o = split_op(t);
        if o.len > 0 && o.len == t.len {
            // An operator that stands alone binds to the next token.
            if i + 1 >= toks.len { return false; }
            if !norm_token(seg, nullset, t, toks[i + 1], inc) { return false; }
            i += 2;
        } else {
            if !norm_token(seg, nullset, "", t, inc) { return false; }
            i += 1;
        }
    }
    return true;
}

// normalize writes the range as strict comparators: sets joined by "||",
// comparators joined by a space. A range that matches every release gives
// the empty text. A null set goes when another set stays; when every set is
// null, the first stays. It returns false when the range is not valid or
// above MAX_RANGE_BYTES.
fn normalize(out: u8[>..]&, range: const u8[:], inc: bool) -> bool {
    // Every call reads a range through here, so the size limit and the
    // count of alternatives stand here, as in parse_range.
    if range.len > MAX_RANGE_BYTES { return false; }
    let sets = split(range, "||");
    if sets.len > MAX_ALTERNATIVES { return false; }
    var all = false;
    // The texts of the sets stand in one buffer; ends marks where each stops.
    var buf: u8[>..] = [];
    var ends: i64[>..] = [];
    var nulls: bool[>..] = [];
    var live: i64 = 0;
    for set in sets {
        var seg: u8[>..] = [];
        var nullset = false;
        if !norm_set(set, seg, nullset, inc) { return false; }
        if nullset { seg.clear(); } else { live += 1; }
        if !nullset && seg.len == 0 { all = true; }
        buf.append(seg);
        ends.push(buf.len);
        nulls.push(nullset);
    }
    if all && sets.len > 1 { return true; }
    var wrote = false;
    var i: i64 = 0;
    while i < ends.len {
        // With several sets, null sets go. When all are null the first stays.
        let skip = sets.len > 1 && nulls[i] && (live > 0 || i > 0);
        if !skip {
            if wrote { out.append("||"); }
            if nulls[i] {
                out.append("<0.0.0-0");
            } else {
                let from: i64 = if i == 0 { 0 } else { ends[i - 1] };
                out.append(buf[from..ends[i]]);
            }
            wrote = true;
        }
        i += 1;
    }
    return true;
}

// valid_range writes the strict form of the range into out, as the npm
// validRange does: "^1.2.3" gives ">=1.2.3 <2.0.0-0". A range that matches
// every release gives "*". It returns false when the range is not valid.
fn valid_range(out: u8[>..]&, range: const u8[:]) -> bool {
    return valid_range_o(out, range, RangeOpts { .. });
}

// valid_range_o is valid_range with the options. The flag changes the
// strict form: "^1.2.x" gives ">=1.2.0-0 <2.0.0-0".
fn valid_range_o(out: u8[>..]&, range: const u8[:], o: RangeOpts) -> bool {
    var norm: u8[>..] = [];
    if !normalize(norm, range, o.include_prerelease) { return false; }
    if norm.len == 0 { out.push('*'); } else { out.append(norm); }
    return true;
}

// satisfies returns true when the version matches the range. The range
// takes the npm forms: >, >=, <, <=, =, ^, ~, x-ranges, "a - b" and "||".
// A version with a pre-release matches only when a comparator of the same
// major, minor and patch carries a pre-release. A bad range matches
// nothing.
fn satisfies(v: Version, range: const u8[:]) -> bool {
    return satisfies_o(v, range, RangeOpts { .. });
}

// satisfies_o is satisfies with the options. With the flag
// `include_prerelease` the range reads as npm reads it with the flag, and
// the same-tuple rule of the pre-release goes off.
fn satisfies_o(v: Version, range: const u8[:], o: RangeOpts) -> bool {
    var norm: u8[>..] = [];
    if !normalize(norm, range, o.include_prerelease) { return false; }
    let sets = split(norm, "||");
    for set in sets {
        if set_matches(v, set, o.include_prerelease) { return true; }
    }
    return false;
}

// set_matches tests one set of strict comparators.
fn set_matches(v: Version, set: const u8[:], inc: bool) -> bool {
    let comps = words(set);
    var pre_ok = false;
    for comp in comps {
        let _, op = split_op(comp);
        let cv, ok = parse(comp[op.len..]);
        if !ok { return false; }
        let c = compare(v, cv);
        var hit = false;
        if op == "" { hit = c == 0; }
        else if op == ">" { hit = c > 0; }
        else if op == ">=" { hit = c >= 0; }
        else if op == "<" { hit = c < 0; }
        else if op == "<=" { hit = c <= 0; }
        if !hit { return false; }
        if cv.pre.len > 0 && cv.major == v.major && cv.minor == v.minor && cv.patch == v.patch {
            pre_ok = true;
        }
    }
    // A pre-release version needs a comparator of its own major, minor and
    // patch that names a pre-release. The flag turns the rule off.
    if v.pre.len > 0 && !inc { return pre_ok; }
    return true;
}
