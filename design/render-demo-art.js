const { chromium } = require('playwright');
const fs = require('fs');
const shows = [
  { file: 'demo-art-0', bg: ['#14213D','#0B1020'], ink: '#F5E6C8', accent: '#FCA311', title: ['THE LONG', 'GAME'], sub: 'Harbour Audio',
    art: `<circle cx="300" cy="230" r="120" fill="none" stroke="#FCA311" stroke-width="18"/><circle cx="300" cy="230" r="72" fill="none" stroke="#F5E6C8" stroke-width="10" stroke-dasharray="20 14"/><circle cx="420" cy="230" r="16" fill="#FCA311"/>` },
  { file: 'demo-art-1', bg: ['#9E1B32','#4A0A16'], ink: '#FFF4E8', accent: '#FFC857', title: ['PAINTED', 'ARMIES'], sub: 'Tabletop Weekly',
    art: `<path d="M300 110 L400 150 L390 260 Q370 320 300 350 Q230 320 210 260 L200 150 Z" fill="#FFC857"/><path d="M300 150 L360 175 L352 255 Q340 295 300 315 Q260 295 248 255 L240 175 Z" fill="#9E1B32"/><rect x="292" y="180" width="16" height="110" fill="#FFF4E8"/><rect x="255" y="215" width="90" height="16" fill="#FFF4E8"/>` },
  { file: 'demo-art-2', bg: ['#2B1B4F','#0E0820'], ink: '#EDE7FF', accent: '#B9A6FF', title: ['NIGHT', 'SHIFT'], sub: 'Ferro Media',
    art: `<circle cx="300" cy="225" r="105" fill="#EDE7FF"/><circle cx="345" cy="195" r="95" fill="#2B1B4F"/><circle cx="170" cy="140" r="6" fill="#B9A6FF"/><circle cx="430" cy="300" r="5" fill="#B9A6FF"/><circle cx="455" cy="130" r="7" fill="#EDE7FF"/><circle cx="150" cy="300" r="4" fill="#EDE7FF"/>` },
  { file: 'demo-art-3', bg: ['#2D6A4F','#12352A'], ink: '#F1FAEE', accent: '#B7E4C7', title: ['FIELD', 'NOTES'], sub: 'Open Air',
    art: `<path d="M300 110 Q420 200 300 350 Q180 200 300 110 Z" fill="#B7E4C7"/><path d="M300 130 L300 340" stroke="#2D6A4F" stroke-width="8"/><path d="M300 200 L250 170 M300 240 L350 205 M300 280 L245 250" stroke="#2D6A4F" stroke-width="7" stroke-linecap="round"/>` },
  { file: 'demo-art-4', bg: ['#E9B44C','#B07D1E'], ink: '#1F1A10', accent: '#1F1A10', title: ['SMALL', 'ENGINES'], sub: 'Garage Radio',
    art: `<g transform="translate(300 230)"><circle r="95" fill="#1F1A10"/><circle r="40" fill="#E9B44C"/>${Array.from({length:10},(_,i)=>`<rect x="-16" y="-125" width="32" height="40" rx="6" fill="#1F1A10" transform="rotate(${i*36})"/>`).join('')}</g>` },
  { file: 'demo-art-5', bg: ['#118AB2','#073B4C'], ink: '#F0FBFF', accent: '#06D6A0', title: ['SECOND', 'OPINION'], sub: 'Clinic Talk',
    art: `<rect x="200" y="130" width="200" height="200" rx="40" fill="#F0FBFF"/><rect x="282" y="160" width="36" height="140" rx="8" fill="#06D6A0"/><rect x="230" y="212" width="140" height="36" rx="8" fill="#06D6A0"/>` },
];
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 600, height: 600 } });
  for (const s of shows) {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600">
      <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${s.bg[0]}"/><stop offset="1" stop-color="${s.bg[1]}"/></linearGradient></defs>
      <rect width="600" height="600" fill="url(#g)"/>${s.art}
      <text x="300" y="450" text-anchor="middle" font-family="DejaVu Sans, Liberation Sans, sans-serif" font-weight="800" font-size="64" letter-spacing="2" fill="${s.ink}">${s.title[0]}</text>
      <text x="300" y="515" text-anchor="middle" font-family="DejaVu Sans, Liberation Sans, sans-serif" font-weight="800" font-size="64" letter-spacing="2" fill="${s.accent === s.ink ? s.ink : s.accent}">${s.title[1]}</text>
      <text x="300" y="565" text-anchor="middle" font-family="DejaVu Sans, Liberation Sans, sans-serif" font-size="24" letter-spacing="3" fill="${s.ink}" opacity="0.75">${s.sub.toUpperCase()}</text></svg>`;
    await p.setContent(`<body style="margin:0">${svg}</body>`);
    await p.screenshot({ path: s.file + '.png' });
  }
  await b.close();
})();
