const { getAuth } = require('../config/firebase');

/**
 * Middleware to verify Firebase ID token from Authorization header.
 * Attaches decoded user info to req.user.
 */
async function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Không có token xác thực' });
  }

  const idToken = authHeader.split('Bearer ')[1];
  try {
    const decoded = await getAuth().verifyIdToken(idToken);
    req.user = {
      uid: decoded.uid,
      email: decoded.email,
      name: decoded.name || decoded.email || 'User',
      picture: decoded.picture || null,
    };
    next();
  } catch (err) {
    console.error('[Auth] Token verification failed:', err.message);
    return res.status(401).json({ error: 'Token không hợp lệ hoặc đã hết hạn' });
  }
}

module.exports = authMiddleware;
