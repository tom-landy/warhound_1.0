// Renders the app icons from the Orbit mark: the primary icon (default, dark and tinted),
// one alternate icon per theme, and the Apple Watch icon.
// Usage (needs Playwright): node design/render-icons.js
//
// Sizing follows the Warhound icon brief, measured on the 1024 master: the mark spans 74%
// (13% margin each side), strokes are 10% (103 px), the moon is 125 px across and the centre
// dot 176 px. Geometry scales; stroke and dots don't. The watch icon is cropped to a circle,
// so there the mark reaches 43% of the canvas from the centre instead.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const dir = __dirname;
const themes = JSON.parse(fs.readFileSync(path.join(dir, 'themes.json'), 'utf8'));

const C = 512;            // canvas centre
const STROKE = 103;       // 10% of 1024
const MOON_R = 62.5;      // 125 px across
const CORE_R = 88;        // 176 px across
const MOON_ANGLE = -45;   // degrees; upper right
const MOON_GAP = 55;      // clear space between each ring end cap and the moon (the old 42 px scaled 1.3x)

/// SVG for the mark whose ring reaches `outer` px from the centre (outer edge of the stroke).
function svg({ outer, top, bottom, background = true, glow = true }) {
  const r = outer - STROKE / 2;
  // Half the angular gap: ring end cap + clear space + moon radius, as a chord at radius r.
  const half = 2 * Math.asin((STROKE / 2 + MOON_GAP + MOON_R) / (2 * r)) * 180 / Math.PI;
  const at = deg => [C + r * Math.cos(deg * Math.PI / 180), C + r * Math.sin(deg * Math.PI / 180)];
  const [sx, sy] = at(MOON_ANGLE - half);   // ring start, above the moon
  const [ex, ey] = at(MOON_ANGLE + half);   // ring end, right of the moon
  const [mx, my] = at(MOON_ANGLE);
  const f = n => n.toFixed(1);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#23262D"/>
      <stop offset="1" stop-color="#0C0D10"/>
    </linearGradient>
    <linearGradient id="fg" gradientUnits="userSpaceOnUse" x1="0" y1="${f(C - outer)}" x2="0" y2="${f(C + outer)}">
      <stop offset="0" stop-color="${top}"/>
      <stop offset="1" stop-color="${bottom}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="${bottom}" stop-opacity="0.22"/>
      <stop offset="1" stop-color="${bottom}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  ${background ? '<rect width="1024" height="1024" fill="url(#bg)"/>' : ''}
  ${glow ? '<rect width="1024" height="1024" fill="url(#glow)"/>' : ''}
  <path d="M ${f(sx)} ${f(sy)} A ${f(r)} ${f(r)} 0 1 0 ${f(ex)} ${f(ey)}" fill="none" stroke="url(#fg)" stroke-width="${STROKE}" stroke-linecap="round"/>
  <circle cx="${f(mx)}" cy="${f(my)}" r="${MOON_R}" fill="url(#fg)"/>
  <circle cx="${C}" cy="${C}" r="${CORE_R}" fill="url(#fg)" opacity="0.9"/>
</svg>
`;
}

const PHONE_OUTER = 1024 * 0.74 / 2;   // 379: 74% span
// The moon sits on the ring's centre line and is wider than the stroke, so it reaches furthest.
const WATCH_OUTER = 1024 * 0.43 - 3 - (MOON_R - STROKE / 2);   // 426: moon within 43%, edge smoothing included

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
  const render = async (file, opts) => {
    const markup = svg(opts);
    await page.setContent(`<html><body style="margin:0;background:transparent">${markup}</body></html>`);
    await page.screenshot({ path: file, omitBackground: !(opts.background ?? true) });
    return markup;
  };
  const ios = path.join(dir, '..', 'Orbit', 'Assets.xcassets');
  for (const t of themes) {
    const name = t.id === 'orange' ? 'AppIcon' : `AppIcon-${t.id}`;
    const set = path.join(ios, `${name}.appiconset`);
    fs.mkdirSync(set, { recursive: true });
    const images = [];
    const markup = await render(path.join(set, `${name}.png`), { outer: PHONE_OUTER, top: t.top, bottom: t.bottom });
    images.push({ filename: `${name}.png`, idiom: 'universal', platform: 'ios', size: '1024x1024' });
    if (t.id === 'orange') {
      fs.writeFileSync(path.join(dir, 'logo-template.svg'), markup);   // reference copy of the master
      // Dark: no background, the system supplies it. Tinted: greyscale; the system applies the tint.
      await render(path.join(set, `${name}-dark.png`), { outer: PHONE_OUTER, top: t.top, bottom: t.bottom, background: false, glow: false });
      await render(path.join(set, `${name}-tinted.png`), { outer: PHONE_OUTER, top: '#FFFFFF', bottom: '#9A9A9A', background: false, glow: false });
      images.push({ appearances: [{ appearance: 'luminosity', value: 'dark' }], filename: `${name}-dark.png`, idiom: 'universal', platform: 'ios', size: '1024x1024' });
      images.push({ appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: `${name}-tinted.png`, idiom: 'universal', platform: 'ios', size: '1024x1024' });
      const watch = path.join(dir, '..', 'OrbitWatch', 'Assets.xcassets', 'AppIcon.appiconset');
      await render(path.join(watch, 'AppIcon.png'), { outer: WATCH_OUTER, top: t.top, bottom: t.bottom });
    }
    fs.writeFileSync(path.join(set, 'Contents.json'), JSON.stringify({ images, info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
    console.log(name);
  }
  await browser.close();
})();
