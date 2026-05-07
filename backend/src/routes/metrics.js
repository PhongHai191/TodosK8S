const router = require("express").Router();
const { register } = require("../middleware/metrics");

router.get("/", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

module.exports = router;
