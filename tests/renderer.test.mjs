import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { renderJob, fixedSvg } from '../renderer/render.mjs';
test('scoped CSS variables preserve node overrides', () => {
  const svg = fixedSvg('<svg xmlns="http://www.w3.org/2000/svg" style="--x:var(--pele-fg)"><g style="--x:#123456"><text fill="var(--x)">A</text></g><text fill="var(--x)">B</text></svg>', {});
  assert.ok(svg.includes('fill="#123456"'));
  assert.ok(svg.includes('fill="#d3c6aa"'));
  assert.ok(!svg.includes('var('));
});
test('Chinese PNG, sequence, cache reuse, origins and palette invalidation', async () => {
  const directory = await mkdtemp(tmpdir() + '/siren-test-');
  try {
    const job = { directory, source: 'flowchart LR\n A[中文编辑] --> B[完成]',
      options: { now: '2026-11-10T00:00:00Z' }, origin: { path: '/project/a.md', block_hash: 'x' } };
    const first = await renderJob(job);
    const png = await readFile(first.path);
    assert.equal(png.subarray(1, 4).toString(), 'PNG');
    assert.ok(first.width > 100 && first.height > 20);
    assert.ok(!(await readFile(first.path.replace('.png', '.svg'), 'utf8')).includes('var('));
    const second = await renderJob({ ...job, origin: { path: '/project/moved/a.md', block_hash: 'x' } });
    assert.equal(second.key, first.key); assert.equal(second.cached, true);
    const meta = JSON.parse(await readFile(first.path.replace('.png', '.json'), 'utf8'));
    assert.equal(meta.origins.length, 2);
    await Promise.all([
      renderJob({ ...job, origin: { path: '/project/b.md', block_hash: 'x' } }),
      renderJob({ ...job, origin: { path: '/project/c.md', block_hash: 'x' } }),
    ]);
    const merged = JSON.parse(await readFile(first.path.replace('.png', '.json'), 'utf8'));
    assert.equal(merged.origins.length, 4);
    const sequence = await renderJob({ ...job, source: 'sequenceDiagram\n participant A as 编辑器\n participant B as 渲染器\n A->>B: 请求\n B-->>A: 图片' });
    assert.notEqual(sequence.key, first.key);
    const theme = await renderJob({ ...job, options: { ...job.options, colors: { '--pele-bg': '#ffffff' } } });
    assert.notEqual(theme.key, first.key);
    await assert.rejects(renderJob({ ...job, source: 'not a diagram' }));
  } finally { await rm(directory, { recursive: true, force: true }); }
});
