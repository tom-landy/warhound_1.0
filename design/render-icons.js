// Renders one app icon per theme from logo-template.svg.
// Usage (needs Playwright): node design/render-icons.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const dir = __dirname;
const out = path.join(dir, '..', 'Warhound', 'Assets.xcassets');
const themes = JSON.parse(fs.readFileSync(path.join(dir, 'themes.json'), 'utf8'));
const template = fs.readFileSync(path.join(dir, 'logo-template.svg'), 'utf8');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
  for (const t of themes) {
    const svg = template.replaceAll('{{TOP}}', t.top).replaceAll('{{BOTTOM}}', t.bottom);
    const name = t.id === 'orange' ? 'AppIcon' : `AppIcon-${t.id}`;
    const set = path.join(out, `${name}.appiconset`);
    fs.mkdirSync(set, { recursive: true });
    await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
    await page.screenshot({ path: path.join(set, `${name}.png`) });
    fs.writeFileSync(path.join(set, 'Contents.json'), JSON.stringify({
      images: [{ filename: `${name}.png`, idiom: 'universal', platform: 'ios', size: '1024x1024' }],
      info: { author: 'xcode', version: 1 },
    }, null, 2) + '\n');
    console.log(name);
  }
  await browser.close();
})();
