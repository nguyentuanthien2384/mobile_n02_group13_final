const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const dbDir = path.join(__dirname, '../mock_db');
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

class MockDocSnapshot {
  constructor(id, data, exists = true) {
    this.id = id;
    this._data = data;
    this.exists = exists;
  }
  data() {
    return this._data;
  }
}

class MockQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.empty = docs.length === 0;
  }
}

class MockDocRef {
  constructor(collectionPath, id) {
    this.collectionPath = collectionPath;
    this.id = id;
    this.filePath = path.join(collectionPath, `${encodeURIComponent(id)}.json`);
  }

  async get() {
    if (!fs.existsSync(this.filePath)) {
      return new MockDocSnapshot(this.id, null, false);
    }
    const raw = fs.readFileSync(this.filePath, 'utf8');
    return new MockDocSnapshot(this.id, JSON.parse(raw), true);
  }

  async set(data, options) {
    let current = {};
    if (fs.existsSync(this.filePath)) {
      current = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
    }
    const finalData = { ...current, ...data };
    fs.mkdirSync(this.collectionPath, { recursive: true });
    fs.writeFileSync(this.filePath, JSON.stringify(finalData, null, 2));
  }

  async update(data) {
    if (!fs.existsSync(this.filePath)) {
      throw new Error('Document does not exist');
    }
    const current = JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
    const finalData = { ...current, ...data };
    fs.writeFileSync(this.filePath, JSON.stringify(finalData, null, 2));
  }

  async delete() {
    if (fs.existsSync(this.filePath)) {
      fs.unlinkSync(this.filePath);
    }
    // Delete subcollections recursively if any
    const subColDir = path.join(this.collectionPath, `sub_${encodeURIComponent(this.id)}`);
    if (fs.existsSync(subColDir)) {
      fs.rmSync(subColDir, { recursive: true, force: true });
    }
  }

  collection(colName) {
    const subColPath = path.join(this.collectionPath, `sub_${encodeURIComponent(this.id)}`, colName);
    return new MockCollection(subColPath);
  }

  get ref() {
    return this;
  }

  get parent() {
    // parent of doc is collection: return parent collection
    const parts = this.collectionPath.split(path.sep);
    // collection path parts, the one before the last is doc ID, the one before that is subcollection name...
    return {
      parent: {
        id: decodeURIComponent(parts[parts.length - 2] || '')
      }
    };
  }
}

class MockCollection {
  constructor(collectionPath) {
    this.collectionPath = collectionPath;
  }

  doc(id) {
    const docId = id || uuidv4();
    return new MockDocRef(this.collectionPath, docId);
  }

  async add(data) {
    const id = uuidv4();
    const docRef = this.doc(id);
    await docRef.set(data);
    return docRef;
  }

  async get() {
    if (!fs.existsSync(this.collectionPath)) {
      return new MockQuerySnapshot([]);
    }
    const files = fs.readdirSync(this.collectionPath).filter(f => f.endsWith('.json'));
    const docs = [];
    for (const f of files) {
      const id = decodeURIComponent(f.slice(0, -5));
      const filePath = path.join(this.collectionPath, f);
      const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      docs.push(new MockDocSnapshot(id, data, true));
    }
    return new MockQuerySnapshot(docs);
  }

  orderBy(field, direction = 'desc') {
    return {
      get: async () => {
        const snap = await this.get();
        snap.docs.sort((a, b) => {
          const valA = a.data()[field];
          const valB = b.data()[field];
          if (valA < valB) return direction === 'asc' ? -1 : 1;
          if (valA > valB) return direction === 'asc' ? 1 : -1;
          return 0;
        });
        return snap;
      }
    };
  }

  where(field, operator, value) {
    return {
      get: async () => {
        const snap = await this.get();
        const docs = snap.docs.filter(doc => {
          const docVal = doc.data()[field];
          if (operator === '==') return docVal === value;
          if (operator === '!=') return docVal !== value;
          return false;
        });
        return new MockQuerySnapshot(docs);
      },
      limit: (n) => ({
        get: async () => {
          const snap = await this.get();
          const docs = snap.docs.filter(doc => doc.data()[field] === value).slice(0, n);
          return new MockQuerySnapshot(docs);
        }
      })
    };
  }
}

class MockBatch {
  constructor() {
    this.ops = [];
  }
  delete(ref) {
    this.ops.push(() => ref.delete());
  }
  set(ref, data) {
    this.ops.push(() => ref.set(data));
  }
  update(ref, data) {
    this.ops.push(() => ref.update(data));
  }
  async commit() {
    for (const op of this.ops) {
      await op();
    }
  }
}

class MockFirestore {
  collection(colName) {
    return new MockCollection(path.join(dbDir, colName));
  }
  collectionGroup(colName) {
    return {
      where: (field, operator, value) => ({
        get: async () => {
          const docs = [];
          const scanDir = (dir) => {
            if (!fs.existsSync(dir)) return;
            const items = fs.readdirSync(dir, { withFileTypes: true });
            for (const item of items) {
              if (item.isDirectory()) {
                if (item.name === colName) {
                  const colPath = path.join(dir, item.name);
                  const files = fs.readdirSync(colPath).filter(f => f.endsWith('.json'));
                  for (const f of files) {
                    const id = decodeURIComponent(f.slice(0, -5));
                    const data = JSON.parse(fs.readFileSync(path.join(colPath, f), 'utf8'));
                    if (data[field] === value) {
                      docs.push({
                        id,
                        data: () => data,
                        ref: new MockDocRef(colPath, id)
                      });
                    }
                  }
                } else {
                  scanDir(path.join(dir, item.name));
                }
              }
            }
          };
          scanDir(dbDir);
          return new MockQuerySnapshot(docs);
        }
      })
    };
  }
  batch() {
    return new MockBatch();
  }
}

module.exports = { MockFirestore };
