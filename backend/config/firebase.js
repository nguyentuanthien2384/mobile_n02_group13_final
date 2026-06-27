const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const { MockFirestore, FieldValue: MockFieldValue } = require('./mockFirebase');
require('dotenv').config();

let initialized = false;
let useMock = false;
let mockDbInstance = null;

function initFirebase() {
  if (initialized) return;

  const hasEnvCreds = process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY;
  const serviceAccountPath = path.join(__dirname, '../serviceAccountKey.json');
  const hasFileCreds = fs.existsSync(serviceAccountPath);

  if (hasEnvCreds) {
    try {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        }),
        storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
      });
      console.log('🚀 [Firebase] Initialized with environment credentials.');
    } catch (err) {
      console.error('❌ [Firebase] Failed to initialize with environment credentials:', err.message);
      useMock = true;
    }
  } else if (hasFileCreds) {
    try {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccountPath),
        storageBucket: process.env.FIREBASE_STORAGE_BUCKET || 'mobile-final-3.firebasestorage.app',
      });
      console.log('🚀 [Firebase] Initialized with serviceAccountKey.json.');
    } catch (err) {
      console.error('❌ [Firebase] Failed to initialize with serviceAccountKey.json:', err.message);
      useMock = true;
    }
  } else {
    console.warn('⚠️  [Firebase] Không tìm thấy credentials. Chạy ở chế độ Mock cục bộ (offline mock mode).');
    useMock = true;
  }
  initialized = true;
}

function getFirestore() {
  initFirebase();
  if (useMock) {
    if (!mockDbInstance) mockDbInstance = new MockFirestore();
    return mockDbInstance;
  }
  return admin.firestore();
}

function getAuth() {
  initFirebase();
  if (useMock) {
    return {
      verifyIdToken: async (idToken) => {
        try {
          const parts = idToken.split('.');
          if (parts.length === 3) {
            const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));
            return {
              uid: payload.sub || payload.user_id || 'mock-user-id',
              email: payload.email || 'mock@example.com',
              name: payload.name || payload.email || 'Mock User',
              picture: payload.picture || null,
            };
          }
        } catch (e) {}
        return {
          uid: 'mock-user-id',
          email: 'mock@example.com',
          name: 'Mock User',
          picture: null,
        };
      },
      getUserByEmail: async (email) => {
        return {
          uid: `mock-uid-${email.replace(/[@.]/g, '-')}`,
          email: email,
          displayName: email.split('@')[0],
        };
      },
      updateUser: async (uid, data) => {
        return { uid, ...data };
      }
    };
  }
  return admin.auth();
}

function getStorage() {
  initFirebase();
  if (useMock) {
    return {
      isMock: true,
      bucket: () => ({
        name: 'mock-bucket',
        file: (name) => {
          const sanitizedName = name.replace(/\//g, '_');
          return {
            save: async (buffer, options) => {
              const uploadDir = path.join(__dirname, '../public/uploads');
              fs.mkdirSync(uploadDir, { recursive: true });
              fs.writeFileSync(path.join(uploadDir, sanitizedName), buffer);
            },
            makePublic: async () => {},
          };
        }
      })
    };
  }
  return admin.storage();
}

function getFieldValue() {
  initFirebase();
  if (useMock) return MockFieldValue;
  return admin.firestore.FieldValue;
}

module.exports = { initFirebase, getFirestore, getAuth, getStorage, getFieldValue };
