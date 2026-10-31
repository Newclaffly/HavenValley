// Renders SVG files to transparent PNGs at 2x with Chromium (Playwright).
//   node tools/art/render_svg.js jobs.json
// jobs.json: [{"svg": path, "png": path, "w": width, "h": height}, ...]
const fs = require('fs');
const { chromium } = require('playwright');

(async () => {
  const jobs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 2 });
  for (const job of jobs) {
    await page.setViewportSize({ width: job.w, height: job.h });
    const svg = fs.readFileSync(job.svg, 'utf8');
    await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await page.screenshot({ path: job.png, omitBackground: true, clip: { x: 0, y: 0, width: job.w, height: job.h } });
  }
  await browser.close();
})();
