require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const path = require('path');
const { initFirebase } = require('./config/firebase');
const authMiddleware = require('./middleware/auth');

// Initialize Firebase Admin
initFirebase();

const app = express();
const PORT = process.env.PORT || 3000;

// ─── Middleware ──────────────────────────────────────────────
app.use('/uploads', express.static(path.join(__dirname, 'public/uploads')));
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',')
    : '*',
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ─── Health check (no auth) ─────────────────────────────────
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    message: 'TodoApp Backend API đang hoạt động',
  });
});

// ─── Public routes (no auth required) ───────────────────────
const notesRouter = require('./routes/notes');
// Public share link - must be before auth middleware
app.get('/api/notes/public/:token', (req, res, next) => {
  // Delegate to notes router
  req.url = `/public/${req.params.token}`;
  notesRouter(req, res, next);
});

// ─── Auth middleware for all /api routes below ──────────────
app.use('/api', authMiddleware);

// ─── API Routes ─────────────────────────────────────────────
app.use('/api/notes', notesRouter);
app.use('/api/tags', require('./routes/tags'));
app.use('/api/folders', require('./routes/folders'));
app.use('/api/users', require('./routes/users'));
app.use('/api/upload', require('./routes/upload'));

// ─── 404 handler ────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint không tồn tại' });
});

// ─── Error handler ──────────────────────────────────────────
app.use((err, req, res, _next) => {
  console.error('[Server] Error:', err);
  if (err.message && err.message.includes('file ảnh')) {
    return res.status(400).json({ error: err.message });
  }
  res.status(500).json({ error: 'Lỗi server nội bộ' });
});

// ─── Start server ───────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`🚀 TodoApp Backend đang chạy trên port ${PORT}`);
  console.log(`📍 Health check: http://localhost:${PORT}/api/health`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
});
