const express = require('express');
const { pool } = require('../db');

const router = express.Router();

router.get('/tasks', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT id, title, done, created_at FROM tasks ORDER BY id DESC LIMIT 100');
    res.json(rows);
  } catch (err) {
    console.error('GET /tasks failed', err);
    res.status(500).json({ error: 'failed to fetch tasks' });
  }
});

router.post('/tasks', async (req, res) => {
  const { title } = req.body || {};
  if (!title || typeof title !== 'string') {
    return res.status(400).json({ error: 'title is required' });
  }
  try {
    const { rows } = await pool.query(
      'INSERT INTO tasks (title) VALUES ($1) RETURNING id, title, done, created_at',
      [title]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('POST /tasks failed', err);
    res.status(500).json({ error: 'failed to create task' });
  }
});

router.patch('/tasks/:id/done', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'UPDATE tasks SET done = true WHERE id = $1 RETURNING id, title, done, created_at',
      [req.params.id]
    );
    if (rows.length === 0) return res.status(404).json({ error: 'not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error('PATCH /tasks/:id/done failed', err);
    res.status(500).json({ error: 'failed to update task' });
  }
});

module.exports = router;
