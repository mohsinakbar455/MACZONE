// Download pinned upstream Lucide assets and rasterize template glyphs for AppKit.
// Run with NODE_PATH pointing to a Node installation containing sharp.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');
const icons = ['layout-grid','monitor','keyboard','palette','shield-check','history','settings','layers','app-window','sliders-horizontal','circle-help','plus','copy','trash-2','check','search','ellipsis','arrow-up-right','arrow-left','arrow-right','download','upload','play','pause','move','maximize','rotate-ccw','folder-open','save','eye','x','chevron-down','external-link','grid-2x2','panels-top-left','scan-line','info','circle-alert'];
async function main() {
  const output = path.join(__dirname, '../Resources/Lucide');
  await fs.mkdir(output, {recursive:true});
  await Promise.all(icons.map(async name => {
    const response = await fetch(`https://unpkg.com/lucide-static@0.468.0/icons/${name}.svg`);
    if (!response.ok) throw Error(`${name}: ${response.status}`);
    const svg = await response.text();
    await fs.writeFile(path.join(output, `${name}.svg`), svg);
    await sharp(Buffer.from(svg)).resize(96,96).png().toFile(path.join(output, `${name}.png`));
  }));
  const license = await fetch('https://unpkg.com/lucide-static@0.468.0/LICENSE');
  if (!license.ok) throw Error('Lucide license download failed');
  await fs.writeFile(path.join(output,'LICENSE'), await license.text());
  console.log(`Saved ${icons.length} Lucide icons (0.468.0) and license.`);
}
main().catch(error => { console.error(error); process.exitCode=1; });
