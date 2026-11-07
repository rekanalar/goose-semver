#!/usr/bin/env node
// Makes test/npm_cases.goose for goose-semver from the npm package semver.
//
// Usage, in the package directory:
//   node test/make_npm_cases.js > test/npm_cases.goose
//
// Every case holds the result that npm gave. The Goose test compares the
// result of the package with it. The seed is fixed, so the output is stable.
// The count of cases goes to standard error.
'use strict';
const semver = require('semver');

// A small seeded generator, so the output does not change.
let state = 20261107;
function rnd() {
  state = (state + 0x6D2B79F5) | 0;
  let t = Math.imul(state ^ (state >>> 15), 1 | state);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const int = (n) => Math.floor(rnd() * n);
const pick = (a) => a[int(a.length)];

const PRES = ['', '', '', '-alpha', '-beta.1', '-beta.2', '-0', '-1', '-rc.1.2'];
const BUILDS = ['', '', '', '', '+a', '+b', '+1', '+10', '+a.1', '+a.b', '+001'];

function version(withBuild) {
  const v = `${int(3)}.${int(4)}.${int(4)}${pick(PRES)}`;
  return withBuild ? v + pick(BUILDS) : v;
}

function partial() {
  const m = int(4), n = int(4), p = int(4);
  switch (int(9)) {
    case 0: return pick(['x', 'X', '*']);
    case 1: return `${m}`;
    case 2: return `${m}.${n}`;
    case 3: return `${m}.x`;
    case 4: return `${m}.${n}.x`;
    case 5: return `${m}.${n}.${p}-${pick(['alpha', 'beta.1', '0', 'rc.1'])}`;
    default: return `${m}.${n}.${p}`;
  }
}

function token() {
  const op = pick(['', '', '=', '>', '>=', '<', '<=', '^', '^', '~', '~>']);
  const gap = int(10) === 0 ? ' ' : '';
  return op + gap + partial();
}

function simpleRange() {
  if (int(8) === 0) return `${partial()} - ${partial()}`;
  const n = 1 + int(3);
  const t = [];
  for (let i = 0; i < n; i++) t.push(token());
  return t.join(' ');
}

function range() {
  const k = int(12);
  if (k === 0) return '*';
  if (k === 1) return '';
  const n = k < 8 ? 1 : 2 + int(2);
  const s = [];
  for (let i = 0; i < n; i++) s.push(simpleRange());
  return s.join(' || ');
}

// A range that npm takes. The package takes the same grammar.
function goodRange() {
  for (;;) {
    const r = range();
    if (semver.validRange(r) !== null) return r;
  }
}

const q = (s) => JSON.stringify(s);
const out = [];
const w = (s) => out.push(s);
const count = { select: 0, sort: 0, compare: 0, minversion: 0, intersects: 0, subset: 0, outside: 0 };

w('// Cases made by test/make_npm_cases.js with npm semver ' + require('semver/package.json').version + '.');
w('// Do not edit by hand. Make the file again with the script.');
w('');
w('namespace npm_cases;');
w('');
w('import std;');
w('import semver from "..";');
w('');
w('// Each list is a text of versions with a space between them.');
w('');
w('fn want_place(vs: const u8[:][:], at: i64, want: const u8[:]) {');
w('    if want == "null" {');
w('        assert(at == -1);');
w('    } else {');
w('        assert(at >= 0 && at < vs.len);');
w('        assert(vs[at] == want);');
w('    }');
w('}');
w('');
w('fn select_case(list: const u8[:], range: const u8[:], mx: const u8[:], mn: const u8[:]) {');
w('    let vs = words(list);');
w('    want_place(vs[..], semver::max_satisfying(vs[..], range), mx);');
w('    want_place(vs[..], semver::min_satisfying(vs[..], range), mn);');
w('}');
w('');
w('fn join_places(vs: const u8[:][:], order: i64[>..]&) -> u8[>..] {');
w('    var s: u8[>..] = [];');
w('    for p, i in order {');
w('        if i > 0 { s.push(\' \'); }');
w('        s.append(vs[p]);');
w('    }');
w('    return s;');
w('}');
w('');
w('fn sort_case(list: const u8[:], asc: const u8[:], desc: const u8[:]) {');
w('    let vs = words(list);');
w('    var order: i64[>..] = [];');
w('    semver::sort(order, vs[..]);');
w('    assert(order.len == vs.len);');
w('    let a = join_places(vs[..], order);');
w('    assert(a[..] == asc);');
w('    semver::rsort(order, vs[..]);');
w('    assert(order.len == vs.len);');
w('    let d = join_places(vs[..], order);');
w('    assert(d[..] == desc);');
w('}');
w('');
w('fn compare_case(a: const u8[:], b: const u8[:], cb: i64, g: bool, ge: bool, l: bool, le: bool, e: bool, ne: bool) {');
w('    let x, ok1 = semver::parse(a);');
w('    let y, ok2 = semver::parse(b);');
w('    assert(ok1 && ok2);');
w('    assert(semver::compare_build(x, y) == cb);');
w('    assert(semver::gt(x, y) == g);');
w('    assert(semver::gte(x, y) == ge);');
w('    assert(semver::lt(x, y) == l);');
w('    assert(semver::lte(x, y) == le);');
w('    assert(semver::eq(x, y) == e);');
w('    assert(semver::neq(x, y) == ne);');
w('}');
w('');
w('fn minversion_case(range: const u8[:], want: const u8[:]) {');
w('    var out: u8[>..] = [];');
w('    let ok = semver::min_version(out, range);');
w('    if want == "null" {');
w('        assert(!ok);');
w('        assert(out.len == 0);');
w('    } else {');
w('        assert(ok);');
w('        assert(out[..] == want);');
w('    }');
w('}');
w('');
w('fn intersects_case(a: const u8[:], b: const u8[:], want: bool) {');
w('    assert(semver::intersects(a, b) == want);');
w('}');
w('');
w('fn subset_case(a: const u8[:], b: const u8[:], want: bool) {');
w('    assert(semver::subset(a, b) == want);');
w('}');
w('');
w('fn outside_case(v: const u8[:], range: const u8[:], hi: bool, lo: bool) {');
w('    let x, ok = semver::parse(v);');
w('    assert(ok);');
w('    assert(semver::gtr(x, range) == hi);');
w('    assert(semver::ltr(x, range) == lo);');
w('    assert(semver::outside(x, range, ">") == hi);');
w('    assert(semver::outside(x, range, "<") == lo);');
w('}');
w('');

// selection
w('fn check_select() {');
for (let i = 0; i < 180; i++) {
  const n = 1 + int(8);
  const list = [];
  // Most versions of a list are releases, so a range often finds one.
  for (let k = 0; k < n; k++) {
    const v = version(int(3) === 0);
    list.push(int(10) < 7 ? v.replace(/-[^+]*/, '') : v);
  }
  // Most ranges name a member of the list, so a version is often found.
  let r;
  if (int(10) < 7) {
    const core = (v) => v.replace(/[-+].*/, '');
    const one = () => pick(['^', '~', '>=', '<', '>', '<=', '', '^', '>=']) + core(pick(list));
    r = int(3) === 0 ? one() + ' ' + one() : (int(4) === 0 ? one() + ' || ' + one() : one());
    if (semver.validRange(r) === null) r = goodRange();
  } else {
    r = goodRange();
  }
  const mx = semver.maxSatisfying(list, r);
  const mn = semver.minSatisfying(list, r);
  w(`    select_case(${q(list.join(' '))}, ${q(r)}, ${q(mx === null ? 'null' : mx)}, ${q(mn === null ? 'null' : mn)});`);
  count.select++;
}
w('}');
w('');

// sort
w('fn check_sort() {');
for (let i = 0; i < 70; i++) {
  const n = 1 + int(9);
  const list = [];
  for (let k = 0; k < n; k++) list.push(version(true));
  const idx = list.map((_, k) => k);
  const asc = idx.slice().sort((a, b) => semver.compareBuild(list[a], list[b]) || 0).map((k) => list[k]);
  const desc = idx.slice().sort((a, b) => semver.compareBuild(list[b], list[a]) || 0).map((k) => list[k]);
  w(`    sort_case(${q(list.join(' '))}, ${q(asc.join(' '))}, ${q(desc.join(' '))});`);
  count.sort++;
}
w('}');
w('');

// compare helpers
w('fn check_compare() {');
for (let i = 0; i < 120; i++) {
  const a = version(true);
  const b = int(4) === 0 ? a.replace(/\+.*/, '') + pick(BUILDS) : version(true);
  w(`    compare_case(${q(a)}, ${q(b)}, ${semver.compareBuild(a, b)}, ${semver.gt(a, b)}, ${semver.gte(a, b)}, ${semver.lt(a, b)}, ${semver.lte(a, b)}, ${semver.eq(a, b)}, ${semver.neq(a, b)});`);
  count.compare++;
}
w('}');
w('');

// min_version
w('fn check_min_version() {');
for (let i = 0; i < 150; i++) {
  const r = goodRange();
  const m = semver.minVersion(r);
  w(`    minversion_case(${q(r)}, ${q(m === null ? 'null' : m.version)});`);
  count.minversion++;
}
w('}');
w('');

// intersects and subset
w('fn check_intersects() {');
for (let i = 0; i < 170; i++) {
  const a = goodRange(), b = goodRange();
  w(`    intersects_case(${q(a)}, ${q(b)}, ${semver.intersects(a, b)});`);
  count.intersects++;
}
w('}');
w('');
w('fn check_subset() {');
for (let i = 0; i < 170; i++) {
  const a = goodRange(), b = goodRange();
  w(`    subset_case(${q(a)}, ${q(b)}, ${semver.subset(a, b)});`);
  count.subset++;
}
w('}');
w('');

// outside
w('fn check_outside() {');
for (let i = 0; i < 160; i++) {
  const v = version(false);
  const r = goodRange();
  w(`    outside_case(${q(v)}, ${q(r)}, ${semver.gtr(v, r)}, ${semver.ltr(v, r)});`);
  count.outside++;
}
w('}');

process.stdout.write(out.join('\n') + '\n');
process.stderr.write('cases: ' + JSON.stringify(count) + ' total=' + Object.values(count).reduce((a, b) => a + b, 0) + '\n');
