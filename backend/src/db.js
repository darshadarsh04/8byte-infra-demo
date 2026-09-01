const { Pool } = require('pg');

// Connection details come in as separate env vars (host/user/password/etc.)
// rather than one DATABASE_URL, because that's how the ECS task definition
// injects the RDS-managed secret - see terraform/modules/ecs-service/main.tf.
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  // a background idle client dying shouldn't take the process down
  console.error('Unexpected error on idle pg client', err);
});

async function ensureSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS tasks (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      done BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
}

module.exports = { pool, ensureSchema };
