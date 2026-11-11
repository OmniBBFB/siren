import { renderJob } from './render.mjs';
let input = '';
for await (const chunk of process.stdin) input += chunk;
try {
  const request = JSON.parse(input);
  const results = [];
  for (const job of request.jobs) {
    try { results.push({ ok: true, ...await renderJob(job) }); }
    catch (error) {
      results.push({ ok: false, error: error.message, line: error.line, column: error.column });
    }
  }
  process.stdout.write(JSON.stringify({ results }) + '\n');
} catch (error) {
  process.stderr.write(error.stack + '\n');
  process.exitCode = 1;
}
