const { Pool } = require("pg");
const logger = require("./utils/logger");

let pool;

const initPromise = (async () => {
  const sslConfig = process.env.DB_SSL === "false" ? false : { rejectUnauthorized: false };
  pool = new Pool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASS,
    database: process.env.DB_NAME,
    port: parseInt(process.env.DB_PORT || "5432", 10),
    ssl: sslConfig,
  });

  pool.on("error", (err) => {
    logger.error("db_pool_error", { error: err.message });
  });

  logger.info("db_connected", { host: process.env.DB_HOST, database: process.env.DB_NAME });
  return pool;
})().catch((err) => {
  logger.error("db_init_failed", { error: err.message });
  throw err;
});

module.exports = {
  query: async (...args) => {
    if (!pool) {
      await initPromise;
    }
    return pool.query(...args);
  },
};
