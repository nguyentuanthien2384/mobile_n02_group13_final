/**
 * MockFirestore — a file-backed, in-process emulation of the Firebase Admin
 * Firestore + FieldValue API. It is used automatically when no Firebase
 * service-account credentials are configured, so the whole backend can run and
 * be tested completely offline.
 *
 * It supports the subset of the Admin SDK that the app actually uses:
 *   - collection / doc / get / set({merge}) / update / delete / add
 *   - where (chained) · orderBy · limit · offset · startAfter
 *   - collectionGroup(name).where(...).orderBy(...).limit(...)
 *   - batch()  · runTransaction()
 *   - FieldValue.increment / arrayUnion / arrayRemove / serverTimestamp / delete
 */
const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const dbDir = path.join(__dirname, '../mock_db');
if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });

// ─── FieldValue sentinels ────────────────────────────────────
const FV = '__mock_fieldvalue__';
const FieldValue = {
  increment: (n) => ({ [FV]: 'increment', value: n }),
  arrayUnion: (...els) => ({ [FV]: 'arrayUnion', elements: els }),
  arrayRemove: (...els) => ({ [FV]: 'arrayRemove', elements: els }),
  serverTimestamp: () => ({ [FV]: 'serverTimestamp' }),
  delete: () => ({ [FV]: 'delete' }),
};

function isSentinel(v) {
  return v && typeof v === 'object' && Object.prototype.hasOwnProperty.call(v, FV);
}

/** Resolve FieldValue sentinels in `data` against the `current` document. */
function applyFieldValues(current, data) {
  const out = { ...current };
  for (const [key, val] of Object.entries(data)) {
    if (isSentinel(val)) {
      const op = val[FV];
      if (op === 'increment') {
        out[key] = (typeof out[key] === 'number' ? out[key] : 0) + val.value;
      } else if (op === 'arrayUnion') {
        const arr = Array.isArray(out[key]) ? [...out[key]] : [];
        for (const el of val.elements) {
          if (!arr.some((x) => JSON.stringify(x) === JSON.stringify(el))) arr.push(el);
        }
        out[key] = arr;
      } else if (op === 'arrayRemove') {
        const arr = Array.isArray(out[key]) ? [...out[key]] : [];
        out[key] = arr.filter((x) => !val.elements.some((el) => JSON.stringify(x) === JSON.stringify(el)));
      } else if (op === 'serverTimestamp') {
        out[key] = new Date().toISOString();
      } else if (op === 'delete') {
        delete out[key];
      }
    } else {
      out[key] = val;
    }
  }
  return out;
}

// ─── Snapshots ───────────────────────────────────────────────
class MockDocSnapshot {
  constructor(id, data, exists = true, ref = null) {
    this.id = id;
    this._data = data;
    this.exists = exists;
    this.ref = ref;
  }
  data() { return this._data; }
  get(field) { return this._data ? this._data[field] : undefined; }
}

class MockQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.empty = docs.length === 0;
    this.size = docs.length;
  }
  forEach(cb) { this.docs.forEach(cb); }
}

// ─── Document reference ──────────────────────────────────────
class MockDocRef {
  constructor(collectionPath, id) {
    this.collectionPath = collectionPath;
    this.id = id;
    this.filePath = path.join(collectionPath, `${encodeURIComponent(id)}.json`);
  }

  async get() {
    if (!fs.existsSync(this.filePath)) return new MockDocSnapshot(this.id, null, false, this);
    const raw = fs.readFileSync(this.filePath, 'utf8');
    return new MockDocSnapshot(this.id, JSON.parse(raw), true, this);
  }

  async set(data, options = {}) {
    let current = {};
    if (options.merge && fs.existsSync(this.filePath)) {
      current = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
    }
    const finalData = applyFieldValues(current, data);
    fs.mkdirSync(this.collectionPath, { recursive: true });
    fs.writeFileSync(this.filePath, JSON.stringify(finalData, null, 2));
    return { writeTime: new Date().toISOString() };
  }

  async update(data) {
    if (!fs.existsSync(this.filePath)) throw new Error('Document does not exist');
    const current = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
    const finalData = applyFieldValues(current, data);
    fs.writeFileSync(this.filePath, JSON.stringify(finalData, null, 2));
    return { writeTime: new Date().toISOString() };
  }

  async delete() {
    if (fs.existsSync(this.filePath)) fs.unlinkSync(this.filePath);
    const subColDir = path.join(this.collectionPath, `sub_${encodeURIComponent(this.id)}`);
    if (fs.existsSync(subColDir)) fs.rmSync(subColDir, { recursive: true, force: true });
  }

  collection(colName) {
    const subColPath = path.join(this.collectionPath, `sub_${encodeURIComponent(this.id)}`, colName);
    return new MockCollection(subColPath);
  }

  get ref() { return this; }

  // The parent of a document is the collection that contains it.
  get parent() {
    return new MockCollection(this.collectionPath);
  }
}

// ─── Query (where / orderBy / limit chain) ───────────────────
function compare(a, b) {
  if (a === undefined || a === null) return b === undefined || b === null ? 0 : -1;
  if (b === undefined || b === null) return 1;
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

class MockQuery {
  constructor(loader, { filters = [], orders = [], limitN = null, offsetN = 0, startAfterDoc = null } = {}) {
    this._loader = loader; // async () => MockDocSnapshot[]
    this._filters = filters;
    this._orders = orders;
    this._limit = limitN;
    this._offset = offsetN;
    this._startAfter = startAfterDoc;
  }

  _clone(over) {
    return new MockQuery(this._loader, {
      filters: this._filters,
      orders: this._orders,
      limitN: this._limit,
      offsetN: this._offset,
      startAfterDoc: this._startAfter,
      ...over,
    });
  }

  where(field, op, value) {
    return this._clone({ filters: [...this._filters, { field, op, value }] });
  }

  orderBy(field, direction = 'asc') {
    return this._clone({ orders: [...this._orders, { field, direction }] });
  }

  limit(n) { return this._clone({ limitN: n }); }
  offset(n) { return this._clone({ offsetN: n }); }
  startAfter(snap) { return this._clone({ startAfterDoc: snap }); }

  _matches(data) {
    return this._filters.every(({ field, op, value }) => {
      const dv = data ? data[field] : undefined;
      switch (op) {
        case '==': return dv === value;
        case '!=': return dv !== value;
        case '>': return compare(dv, value) > 0;
        case '>=': return compare(dv, value) >= 0;
        case '<': return compare(dv, value) < 0;
        case '<=': return compare(dv, value) <= 0;
        case 'in': return Array.isArray(value) && value.includes(dv);
        case 'not-in': return Array.isArray(value) && !value.includes(dv);
        case 'array-contains': return Array.isArray(dv) && dv.includes(value);
        case 'array-contains-any': return Array.isArray(dv) && Array.isArray(value) && value.some((v) => dv.includes(v));
        default: return false;
      }
    });
  }

  async get() {
    let docs = (await this._loader()).filter((d) => this._matches(d.data()));

    for (const { field, direction } of [...this._orders].reverse()) {
      docs.sort((a, b) => {
        const c = compare(a.data()[field], b.data()[field]);
        return direction === 'desc' ? -c : c;
      });
    }

    if (this._startAfter) {
      const idx = docs.findIndex((d) => d.id === this._startAfter.id);
      if (idx >= 0) docs = docs.slice(idx + 1);
    }
    if (this._offset) docs = docs.slice(this._offset);
    if (this._limit != null) docs = docs.slice(0, this._limit);
    return new MockQuerySnapshot(docs);
  }
}

// ─── Collection ──────────────────────────────────────────────
class MockCollection {
  constructor(collectionPath) {
    this.collectionPath = collectionPath;
  }

  // Collection id = last path segment (e.g. 'shares', 'notes').
  get id() {
    const parts = this.collectionPath.split(path.sep);
    return decodeURIComponent(parts[parts.length - 1] || '');
  }

  // The parent of a subcollection is the document that owns it. Subcollections
  // live under a `sub_<encodedDocId>` folder; top-level collections have no parent.
  get parent() {
    const parts = this.collectionPath.split(path.sep);
    const ownerFolder = parts[parts.length - 2] || '';
    if (!ownerFolder.startsWith('sub_')) return null;
    const docId = decodeURIComponent(ownerFolder.slice(4));
    const docCollectionPath = parts.slice(0, parts.length - 2).join(path.sep);
    return new MockDocRef(docCollectionPath, docId);
  }

  doc(id) { return new MockDocRef(this.collectionPath, id || uuidv4()); }

  async add(data) {
    const ref = this.doc(uuidv4());
    await ref.set(data);
    return ref;
  }

  _loadAll() {
    return async () => {
      if (!fs.existsSync(this.collectionPath)) return [];
      const files = fs.readdirSync(this.collectionPath).filter((f) => f.endsWith('.json'));
      return files.map((f) => {
        const id = decodeURIComponent(f.slice(0, -5));
        const data = JSON.parse(fs.readFileSync(path.join(this.collectionPath, f), 'utf8'));
        return new MockDocSnapshot(id, data, true, new MockDocRef(this.collectionPath, id));
      });
    };
  }

  _query() { return new MockQuery(this._loadAll()); }

  where(f, o, v) { return this._query().where(f, o, v); }
  orderBy(f, d) { return this._query().orderBy(f, d); }
  limit(n) { return this._query().limit(n); }
  offset(n) { return this._query().offset(n); }

  async get() { return this._query().get(); }
}

// ─── Batch ───────────────────────────────────────────────────
class MockBatch {
  constructor() { this.ops = []; }
  set(ref, data, options) { this.ops.push(() => ref.set(data, options)); return this; }
  update(ref, data) { this.ops.push(() => ref.update(data)); return this; }
  delete(ref) { this.ops.push(() => ref.delete()); return this; }
  async commit() { for (const op of this.ops) await op(); }
}

// ─── collectionGroup loader ──────────────────────────────────
function collectionGroupLoader(colName) {
  return async () => {
    const docs = [];
    const scan = (dir) => {
      if (!fs.existsSync(dir)) return;
      for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
        if (!item.isDirectory()) continue;
        if (item.name === colName) {
          const colPath = path.join(dir, item.name);
          for (const f of fs.readdirSync(colPath).filter((x) => x.endsWith('.json'))) {
            const id = decodeURIComponent(f.slice(0, -5));
            const data = JSON.parse(fs.readFileSync(path.join(colPath, f), 'utf8'));
            docs.push(new MockDocSnapshot(id, data, true, new MockDocRef(colPath, id)));
          }
        } else {
          scan(path.join(dir, item.name));
        }
      }
    };
    scan(dbDir);
    return docs;
  };
}

// ─── Firestore root ──────────────────────────────────────────
class MockFirestore {
  collection(colName) { return new MockCollection(path.join(dbDir, colName)); }
  collectionGroup(colName) { return new MockQuery(collectionGroupLoader(colName)); }
  batch() { return new MockBatch(); }
  async runTransaction(fn) {
    // Mock transaction: no isolation, runs sequentially with a thin wrapper.
    const tx = {
      get: (ref) => ref.get(),
      set: (ref, data, opt) => ref.set(data, opt),
      update: (ref, data) => ref.update(data),
      delete: (ref) => ref.delete(),
    };
    return fn(tx);
  }
}

module.exports = { MockFirestore, FieldValue, applyFieldValues };
