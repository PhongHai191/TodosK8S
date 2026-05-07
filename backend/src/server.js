const express = require("express");
const noCache = require("./middleware/noCache");
const { metricsMiddleware } = require("./middleware/metrics");
const httpLogger = require("./middleware/httpLogger");
const logger = require("./utils/logger");

const app = express();

app.use(express.json());
app.use(metricsMiddleware);
app.use(httpLogger);
app.use("/metrics", require("./routes/metrics"));
app.use("/health", require("./routes/health"));
app.use("/api", noCache);
app.use("/api/auth", require("./routes/auth"));
app.use("/api/todos", require("./routes/todo"));
app.use("/api/profile", require("./routes/profile"));

app.use((err, req, res, next) => {
  logger.error("unhandled_error", {
    error: err.message,
    stack: err.stack,
    method: req.method,
    path: req.path,
  });
  res.status(500).json({ error: "Internal server error" });
});

app.listen(3000, () => logger.info("server_started", { port: 3000 }));
