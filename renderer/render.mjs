import { render } from 'pele';
import { Resvg } from '@resvg/resvg-js';
import { DOMParser, XMLSerializer } from '@xmldom/xmldom';
import { createHash } from 'node:crypto';
import { readFile, writeFile, rename, mkdir, stat, open, unlink } from 'node:fs/promises';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
export const versions = {
  pele: require('pele/package.json').version,
  resvg: require('@resvg/resvg-js/package.json').version,
  pipeline: 1,
};
export const palette = {
  '--pele-bg': '#1e2326', '--pele-fg': '#d3c6aa',
  '--pele-muted': '#9da9a0', '--pele-line': '#a7c080',
  '--pele-surface': '#2d353b', '--pele-surface-alt': '#343f44',
  '--pele-border': '#859289', '--pele-accent': '#7fbbb3',
  '--pele-fg-on-light': '#272e33', '--pele-fg-on-dark': '#d3c6aa',
};
// Pele emits inline styles. Resolve custom properties per element so classDef
// overrides do not accidentally leak to siblings.
export function fixedSvg(svg, colors) {
  const doc = new DOMParser().parseFromString(svg, 'image/svg+xml');
  function resolve(value, vars, depth = 0) {
    if (depth > 32) throw new Error('CSS variable recursion limit');
    let pos;
    while ((pos = value.indexOf('var(')) !== -1) {
      let end = pos + 4, level = 1;
      for (; end < value.length && level; end++) {
        if (value[end] === '(') level++;
        if (value[end] === ')') level--;
      }
      if (level) throw new Error('Unclosed CSS variable');
      const body = value.slice(pos + 4, end - 1);
      const comma = body.indexOf(',');
      const key = (comma === -1 ? body : body.slice(0, comma)).trim();
      const fallback = comma === -1 ? undefined : body.slice(comma + 1).trim();
      const raw = vars[key] ?? fallback;
      if (raw === undefined) throw new Error('Unresolved CSS variable: ' + key);
      value = value.slice(0, pos) + resolve(raw, vars, depth + 1) + value.slice(end);
    }
    return value;
  }
  function walk(el, inherited) {
    const vars = { ...inherited };
    const declarations = (el.getAttribute('style') || '').split(';')
      .filter(Boolean).map(s => {
        const i = s.indexOf(':');
        return [s.slice(0, i).trim(), s.slice(i + 1).trim()];
      });
    for (const [key, value] of declarations) {
      if (key.startsWith('--')) vars[key] = value;
    }
    const styles = declarations.filter(([key]) => !key.startsWith('--'))
      .map(([key, value]) => key + ':' + resolve(value, vars));
    if (styles.length) el.setAttribute('style', styles.join(';'));
    else el.removeAttribute('style');
    for (const attr of Array.from(el.attributes || [])) {
      if (attr.value.includes('var(')) el.setAttribute(attr.name, resolve(attr.value, vars));
    }
    for (const child of Array.from(el.childNodes || [])) {
      if (child.nodeType === 1) walk(child, vars);
    }
  }
  walk(doc.documentElement, { ...palette, ...colors });
  return new XMLSerializer().serializeToString(doc);
}
async function json(path) {
  try { return JSON.parse(await readFile(path, 'utf8')); } catch { return null; }
}
async function atomic(path, value) {
  const tmp = path + '.' + process.pid + '.tmp';
  await writeFile(tmp, value);
  await rename(tmp, path);
}
async function locked(base, fn) {
  const path = base + '.lock';
  const deadline = Date.now() + 25000;
  let handle;
  while (!handle) {
    try {
      handle = await open(path, 'wx');
      await handle.writeFile(String(process.pid));
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const owner = Number(await readFile(path, 'utf8').catch(() => ''));
      if (owner > 0) {
        try { process.kill(owner, 0); }
        catch (e) { if (e.code === 'ESRCH') await unlink(path).catch(() => {}); }
      } else {
        const info = await stat(path).catch(() => null);
        if (info && Date.now() - info.mtimeMs > 30000) await unlink(path).catch(() => {});
      }
      if (Date.now() > deadline) throw new Error('Timed out waiting for cache lock');
      await new Promise(resolve => setTimeout(resolve, 20));
    }
  }
  try { return await fn(); }
  finally { await handle.close(); await unlink(path).catch(() => {}); }
}
export async function renderJob(job) {
  const opts = {
    font: 'Noto Sans CJK SC', font_size: 16, scale: 2,
    colors: {}, ...job.options,
  };
  if (!(opts.scale >= 0.5 && opts.scale <= 4)) throw new Error('scale must be between 0.5 and 4');
  const identity = { source: job.source, options: opts, versions };
  const key = createHash('sha256').update(JSON.stringify(identity)).digest('hex');
  const base = job.directory + '/' + key;
  await mkdir(job.directory, { recursive: true });
  return locked(base, async () => {
    let meta = await json(base + '.json');
    const valid = meta && await stat(base + '.png').then(s => s.size > 24, () => false);
    if (!valid) {
      const result = render(job.source, {
        fontFamily: opts.font, fontSize: opts.font_size,
        fontFamilyMono: opts.font_mono || 'monospace',
        responsive: false, autoDirection: false,
        images: false, links: false, now: opts.now ? new Date(opts.now) : undefined,
        limit: 50000, outputLimit: 4000000,
      });
      if (result.width * result.height * opts.scale ** 2 > 32_000_000) throw new Error('Diagram exceeds 32 megapixels');
      const svg = fixedSvg(result.svg, opts.colors);
      const png = new Resvg(svg, {
        background: opts.colors['--pele-bg'] || palette['--pele-bg'],
        font: { loadSystemFonts: true, defaultFontFamily: opts.font },
        fitTo: { mode: 'zoom', value: opts.scale },
      }).render();
      if (png.width * png.height > 32_000_000) throw new Error('Diagram exceeds 32 megapixels');
      await atomic(base + '.svg', svg);
      await atomic(base + '.png', png.asPng());
      meta = {
        schema: 1, key, source_hash: createHash('sha256').update(job.source).digest('hex'),
        width: png.width, height: png.height, renderer: versions, options: opts,
        created_at: new Date().toISOString(), origins: [],
      };
    }
    const origin = { ...job.origin, last_seen: new Date().toISOString() };
    meta.origins = (meta.origins || []).filter(o =>
      !(o.path === origin.path && o.block_hash === origin.block_hash));
    meta.origins.push(origin);
    meta.last_used = new Date().toISOString();
    await atomic(base + '.json', JSON.stringify(meta, null, 2) + '\n');
    return { path: base + '.png', key, width: meta.width, height: meta.height, cached: !!valid };
  });
}
