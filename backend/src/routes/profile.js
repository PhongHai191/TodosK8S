const router = require("express").Router();
const { getUploadUrl, getAvatarUrl } = require("../utils/s3");
const db = require("../db");
const auth = require("../middleware/authMiddleware");
const logger = require("../utils/logger");

router.use(auth);

router.get("/", async (req, res) => {
  try {
    const result = await db.query(
      "SELECT username,email,fullname,phone,avatar FROM users WHERE id=$1",
      [req.user.id]
    );
    const user = result.rows[0];
    let avatarUrl = null;
    if (user.avatar) {
      avatarUrl = await getAvatarUrl(user.avatar);
    }
    res.json({ ...user, avatar: avatarUrl });
  } catch (err) {
    logger.error("profile_get_error", { error: err.message, userId: req.user.id });
    res.status(500).json({ error: "Server error" });
  }
});

router.put("/", async (req, res) => {
  try {
    const { fullname, email, phone } = req.body;
    await db.query(
      "UPDATE users SET fullname=$1,email=$2,phone=$3 WHERE id=$4",
      [fullname, email, phone, req.user.id]
    );
    logger.info("profile_updated", { userId: req.user.id });
    res.sendStatus(200);
  } catch (err) {
    logger.error("profile_update_error", { error: err.message, userId: req.user.id });
    res.status(500).json({ error: "Server error" });
  }
});

router.get("/upload-url", async (req, res) => {
  try {
    const { filename, type } = req.query;
    if (!filename || !type) {
      return res.status(400).json({ error: "Missing filename or type" });
    }
    const data = await getUploadUrl(filename, type);
    res.json(data);
  } catch (err) {
    logger.error("avatar_upload_url_error", { error: err.message, userId: req.user.id });
    res.status(500).json({ error: "Server error" });
  }
});

router.post("/avatar", async (req, res) => {
  try {
    const { key } = req.body;
    if (!key) {
      return res.status(400).json({ error: "Missing key" });
    }
    await db.query(
      "UPDATE users SET avatar=$1 WHERE id=$2",
      [key, req.user.id]
    );
    logger.info("avatar_updated", { userId: req.user.id });
    res.sendStatus(200);
  } catch (err) {
    logger.error("avatar_update_error", { error: err.message, userId: req.user.id });
    res.status(500).json({ error: "Server error" });
  }
});

module.exports = router;
