const express = require('express');
const client = require('prom-client');
const { ensureSchema, pool } = require('./db');
const tasksRouter = require('./routes/tasks');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

// --- Prometheus-format metrics, scraped by CloudWatch agent / Container Insights ---
// Kept even though the assignment targets CloudWatch dashboards, since it costs
// nothing to expose and makes a future Prometheus/Grafana swap a non-event.
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
});
register.registerMetric(httpRequestDuration);

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});
register.registerMetric(httpRequestsTotal);

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    end({ method: req.method, route, status_code: res.statusCode });
    httpRequestsTotal.inc({ method: req.method, route, status_code: res.statusCode });
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// --- Health checks ---
// /health = process is up (used by ECS container health check)
// /ready  = process is up AND can reach the database (used by ALB target group)
app.get('/health', (req, res) => res.status(200).json({ status: 'ok' }));

app.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch (err) {
    res.status(503).json({ status: 'not-ready', error: err.message });
  }
});

app.use('/api', tasksRouter);

async function start() {
  try {
    await ensureSchema();
  } catch (err) {
    // don't crash-loop the container if the DB isn't reachable yet at boot -
    // /ready will just report unhealthy until it recovers
    console.error('Schema init failed, will retry lazily on first query', err);
  }
  app.listen(port, () => console.log(`8bytes-demo backend listening on ${port}`));
}

start();
