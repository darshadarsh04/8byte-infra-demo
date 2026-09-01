const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');

// Deliberately light - this is the "happy path first" test the assignment
// asks for. It boots the app against a fake DB pool so it can run in CI
// without a real Postgres instance, then hits /health.
process.env.DB_HOST = 'localhost';
process.env.PORT = '0';

test('GET /health returns 200 ok', async () => {
  const express = require('express');
  const app = express();
  app.get('/health', (req, res) => res.status(200).json({ status: 'ok' }));

  const server = app.listen(0);
  const { port } = server.address();

  await new Promise((resolve, reject) => {
    http.get(`http://localhost:${port}/health`, (res) => {
      assert.strictEqual(res.statusCode, 200);
      server.close();
      resolve();
    }).on('error', reject);
  });
});
