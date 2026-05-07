const router = require("express").Router();
const db = require("../db");
const redis = require("../redis");
const auth = require("../middleware/authMiddleware");
const logger = require("../utils/logger");

router.use(auth);

// GET TODOS
router.get("/", async (req, res) => {
  try {
    const key = `todos:${req.user.id}`;
    const cached = await redis.get(key);
    if (cached) return res.json(JSON.parse(cached));

    const result = await db.query(
      "SELECT id,text FROM todos WHERE user_id=$1",
      [req.user.id]
    );

    await redis.set(key, JSON.stringify(result.rows), { EX: 60 });
    res.json(result.rows);
  } catch (err) {
    logger.error("todo_get_error", { error: err.message, userId: req.user.id });
    res.status(500).json({ error: "Server error" });
  }
});

// CREATE
router.post("/", async (req, res) => {
  try {
    const { text } = req.body;
    const result = await db.query(
      "INSERT INTO todos(text,user_id) VALUES($1,$2) RETURNING id,text",
      [text, req.user.id]
    );
    await redis.del(`todos:${req.user.id}`);
    logger.info("todo_created", { todoId: result.rows[0].id, userId: req.user.id });
    res.status(201).json(result.rows[0]);
  } catch (err) {
    logger.error("todo_create_error", { error: err.message, userId: req.user.id });
    res.status(500).json({ error: "Server error" });
  }
});

// DELETE
router.delete("/:id", async (req, res) => {
  try {
    await db.query(
      "DELETE FROM todos WHERE id=$1 AND user_id=$2",
      [req.params.id, req.user.id]
    );
    await redis.del(`todos:${req.user.id}`);
    logger.info("todo_deleted", { todoId: req.params.id, userId: req.user.id });
    res.sendStatus(204);
  } catch (err) {
    logger.error("todo_delete_error", { error: err.message, todoId: req.params.id, userId: req.user.id });
    res.status(500).json({ error: "Server error" });
  }
});

module.exports = router;
