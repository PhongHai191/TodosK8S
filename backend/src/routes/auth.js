const router = require("express").Router();
const db = require("../db");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const redis = require("../redis");
const ms = require("ms");
const logger = require("../utils/logger");

// REGISTER
router.post("/register", async (req, res) => {
  const { username, password, email, fullname, phone } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: "Missing username/password" });
  }

  try {
    const hash = await bcrypt.hash(password, 10);

    const result = await db.query(
      `
      INSERT INTO users(username, password, email, fullname, phone)
      VALUES($1, $2, $3, $4, $5)
      RETURNING id, username, email, fullname, phone
      `,
      [username, hash, email || null, fullname || null, phone || null]
    );

    logger.info("user_registered", { userId: result.rows[0].id, username });
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === "23505") {
      logger.warn("register_duplicate_username", { username });
      return res.status(400).json({ error: "Username already exists" });
    }
    logger.error("register_error", { error: err.message, username });
    res.status(500).json({ error: "Server error" });
  }
});

// LOGIN
router.post("/login", async (req, res) => {
  const { username, password } = req.body;

  try {
    const result = await db.query(
      "SELECT * FROM users WHERE username=$1",
      [username]
    );

    const user = result.rows[0];
    if (!user) {
      logger.warn("login_user_not_found", { username, ip: req.ip });
      return res.sendStatus(401);
    }

    const valid = await bcrypt.compare(password, user.password);
    if (!valid) {
      logger.warn("login_wrong_password", { username, ip: req.ip });
      return res.sendStatus(401);
    }

    const accessToken = jwt.sign(
      { id: user.id },
      process.env.JWT_ACCESS_SECRET,
      { expiresIn: process.env.ACCESS_EXPIRE }
    );

    const refreshToken = jwt.sign(
      { id: user.id },
      process.env.JWT_REFRESH_SECRET,
      { expiresIn: process.env.REFRESH_EXPIRE }
    );
    const ttl = ms(process.env.REFRESH_EXPIRE) / 1000;
    await redis.set(`refresh:${user.id}`, refreshToken, "EX", ttl);

    logger.info("login_success", { userId: user.id, username, ip: req.ip });
    res.json({ accessToken, refreshToken });
  } catch (err) {
    logger.error("login_error", { error: err.message, username });
    res.status(500).json({ error: "Server error" });
  }
});

// LOGOUT
router.post("/logout", async (req, res) => {
  const { refreshToken } = req.body;

  if (!refreshToken) return res.sendStatus(400);

  try {
    const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    await redis.del(`refresh:${decoded.id}`);
    logger.info("logout", { userId: decoded.id });
    res.sendStatus(200);
  } catch {
    res.sendStatus(200);
  }
});

// REFRESH TOKEN
router.post("/refresh", async (req, res) => {
  const { refreshToken } = req.body;

  try {
    const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);

    const stored = await redis.get(`refresh:${decoded.id}`);
    if (stored !== refreshToken) return res.sendStatus(403);

    const newAccess = jwt.sign(
      { id: decoded.id },
      process.env.JWT_ACCESS_SECRET,
      { expiresIn: process.env.ACCESS_EXPIRE }
    );

    res.json({ accessToken: newAccess });
  } catch {
    res.sendStatus(403);
  }
});

module.exports = router;
