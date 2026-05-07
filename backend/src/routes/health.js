const express = require("express");
const router = express.Router();
const db = require("../db");
const logger = require("../utils/logger");

router.get("/", (req, res) => {
  res.sendStatus(200);
});

router.get("/db", async (req, res) => {
  try {
    await db.query("SELECT 1");
    res.status(200).json({ status: "OK" });
  } catch (err) {
    logger.error("health_db_failed", { error: err.message });
    res.status(500).json({ status: "DB FAIL", details: err.message });
  }
});

module.exports = router;
