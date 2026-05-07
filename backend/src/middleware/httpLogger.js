const logger = require("../utils/logger");

module.exports = (req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    if (req.path.startsWith("/health") || req.path === "/metrics" || req.path === "/") return;
    logger.info("http_request", {
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration_ms: Date.now() - start,
      user_id: req.user?.id ?? null,
      ip: req.ip,
    });
  });
  next();
};
