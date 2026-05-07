const { createClient } = require("redis");
const logger = require("./utils/logger");

const client = createClient({
  url: `redis://${process.env.REDIS_HOST}:6379`,
});

client.on("error", (err) => {
  logger.error("redis_error", { error: err.message });
});

(async () => {
  try {
    await client.connect();
    logger.info("redis_connected", { host: process.env.REDIS_HOST });
  } catch (err) {
    logger.error("redis_connect_failed", { error: err.message });
  }
})();

module.exports = client;
