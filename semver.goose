// semver - semantic versions for Goose.
//
// The package parses, compares, and formats versions in the SemVer 2.0.0
// form: MAJOR.MINOR.PATCH, then an optional pre-release, then optional
// build metadata.
//
// The repository is goose-semver. The package name is what a program
// imports it by, so the name is "semver".
//
// Every file in this package declares "namespace semver;". A user calls
// semver::parse. A user calls semver::compare.
namespace semver;

import std;

// Version holds one version. The pre-release and the build metadata are
// slices into the string that the parse read, so they stay valid only as
// long as that string.
struct Version {
    major: i32,
    minor: i32,
    patch: i32,
    pre: const u8[:],
    build: const u8[:],
}

// parse reads one version. It returns false when the text is not a
// version in the SemVer form. The pre-release and the build fields of the
// result refer to the input.
fn parse(s: const u8[:]) -> Version, bool {
    var v = Version { major: 0, minor: 0, patch: 0, pre: "", build: "" };

    // The build metadata starts at the first '+' and is not part of the
    // comparison.
    var core = s;
    let plus = find(core, "+");
    if plus >= 0 {
        v.build = core[plus + 1..];
        core = core[..plus];
    }
    // The pre-release starts at the first '-' after the core numbers.
    let dash = find(core, "-");
    if dash >= 0 {
        v.pre = core[dash + 1..];
        core = core[..dash];
    }

    // Three numbers separated by two dots.
    let first = find(core, ".");
    if first < 0 { return v, false; }
    let second = find(core[first + 1..], ".");
    if second < 0 { return v, false; }
    let mid = first + 1 + second;

    let ma, ok1 = parse_num(core[..first]);
    let mi, ok2 = parse_num(core[first + 1..mid]);
    let pa, ok3 = parse_num(core[mid + 1..]);
    if !ok1 || !ok2 || !ok3 { return v, false; }

    // A number has no leading zero, unless it is the number zero.
    if !num_form(core[..first]) || !num_form(core[first + 1..mid]) || !num_form(core[mid + 1..]) {
        return v, false;
    }

    if !pre_form(v.pre) { return v, false; }
    if !build_form(v.build) { return v, false; }

    v.major = ma;
    v.minor = mi;
    v.patch = pa;
    return v, true;
}

// parse_num reads the digits of one number. It returns false when the
// text is empty or holds something that is not a digit.
fn parse_num(s: const u8[:]) -> i32, bool {
    if s.len == 0 { return 0, false; }
    var n: i64 = 0;
    for c in s {
        if c < '0' || c > '9' { return 0, false; }
        n = n * 10 + (c - '0');
        if n > 0x7fffffff { return 0, false; }
    }
    return n as i32, true;
}

// num_form returns true when the number has the written form of the
// standard: digits, and no leading zero unless the number is "0".
fn num_form(s: const u8[:]) -> bool {
    if s.len == 0 { return false; }
    if s.len > 1 && s[0] == '0' { return false; }
    for c in s {
        if c < '0' || c > '9' { return false; }
    }
    return true;
}

// ident_form returns true when one part of a pre-release or of the build
// metadata holds only the characters that the standard allows.
fn ident_form(s: const u8[:], numbers_may_lead_zero: bool) -> bool {
    if s.len == 0 { return false; }
    var all_digits = true;
    var i = 0;
    while i < s.len {
        let c = s[i];
        let digit = c >= '0' && c <= '9';
        let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        if c == '-' || c == '.' {
            // A part boundary. An empty part is a fault.
            if i == 0 || i == s.len - 1 { return false; }
            if s[i - 1] == '.' || s[i + 1] == '.' { return false; }
            all_digits = false;
            i += 1;
            continue;
        }
        if !digit && !alpha { return false; }
        if !digit { all_digits = false; }
        i += 1;
    }
    // A numeric part of a pre-release has no leading zero. The build
    // metadata may hold leading zeros.
    if all_digits && !numbers_may_lead_zero {
        let first_part = find(s, ".");
        let part = if first_part < 0 { s } else { s[..first_part] };
        return num_form(part);
    }
    return true;
}

// pre_form returns true when the pre-release has the form of the standard.
fn pre_form(s: const u8[:]) -> bool {
    if s.len == 0 { return true; }
    return ident_form(s, false);
}

// build_form returns true when the build metadata has the form of the
// standard.
fn build_form(s: const u8[:]) -> bool {
    if s.len == 0 { return true; }
    return ident_form(s, true);
}

// compare puts a before b. It gives a negative number when a comes first,
// a positive one when b comes first, and zero when the versions hold the
// same precedence. The build metadata takes no part in the order.
fn compare(a: Version, b: Version) -> i64 {
    if a.major != b.major { return a.major - b.major; }
    if a.minor != b.minor { return a.minor - b.minor; }
    if a.patch != b.patch { return a.patch - b.patch; }
    // A version with a pre-release comes before one without.
    if a.pre.len == 0 && b.pre.len == 0 { return 0; }
    if a.pre.len == 0 { return 1; }
    if b.pre.len == 0 { return -1; }
    return compare_pre(a.pre, b.pre);
}

// compare_pre compares two pre-release strings, part by part.
fn compare_pre(a: const u8[:], b: const u8[:]) -> i64 {
    var ai = 0;
    var bi = 0;
    loop {
        let a_done = ai >= a.len;
        let b_done = bi >= b.len;
        if a_done && b_done { return 0; }
        // The shorter one comes first, when one is a prefix of the other.
        if a_done { return -1; }
        if b_done { return 1; }
        let a_end = part_end(a, ai);
        let b_end = part_end(b, bi);
        let ap = a[ai..a_end];
        let bp = b[bi..b_end];
        let a_num = is_numeric(ap);
        let b_num = is_numeric(bp);
        if a_num && b_num {
            let an, _ = parse_num(ap);
            let bn, _ = parse_num(bp);
            if an != bn { return an - bn; }
        } else if a_num {
            // Numbers come before letters.
            return -1;
        } else if b_num {
            return 1;
        } else {
            let order = compare_text(ap, bp);
            if order != 0 { return order; }
        }
        ai = a_end + 1;
        bi = b_end + 1;
    }
}

// part_end gives the index after the part that starts at start. A part
// ends before the next dot or at the end.
fn part_end(s: const u8[:], start: i64) -> i64 {
    var i = start;
    while i < s.len && s[i] != '.' { i += 1; }
    return i;
}

// compare_text compares two parts byte by byte. The shorter one comes
// first when one is a prefix of the other.
fn compare_text(a: const u8[:], b: const u8[:]) -> i64 {
    let n = if a.len < b.len { a.len } else { b.len };
    var i = 0;
    while i < n {
        if a[i] != b[i] {
            return if a[i] < b[i] { -1 } else { 1 };
        }
        i += 1;
    }
    if a.len == b.len { return 0; }
    return if a.len < b.len { -1 } else { 1 };
}

// is_numeric returns true when the part holds digits only.
fn is_numeric(s: const u8[:]) -> bool {
    if s.len == 0 { return false; }
    for c in s {
        if c < '0' || c > '9' { return false; }
    }
    return true;
}

// format writes the version into out. It holds the build metadata.
fn format(out: u8[>..]&, v: Version) {
    format(out, v.major);
    out.push('.');
    format(out, v.minor);
    out.push('.');
    format(out, v.patch);
    if v.pre.len > 0 {
        out.push('-');
        out.append(v.pre);
    }
    if v.build.len > 0 {
        out.push('+');
        out.append(v.build);
    }
}
