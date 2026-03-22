#!/usr/bin/env node
// Capture replay UI screenshots for README documentation.
// Usage: node assets/capture-replay-screenshots.js /path/to/replay.html
//
// Requires: npx playwright (auto-downloads Chromium if needed)
// Outputs: assets/screenshot-replay*.png

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const VIEWPORT = { width: 1400, height: 900 };
const DEVICE_SCALE = 2;
const ASSETS_DIR = path.join(__dirname);

async function main() {
  const replayPath = process.argv[2];
  if (!replayPath) {
    console.error('Usage: node capture-replay-screenshots.js <path-to-replay.html>');
    process.exit(1);
  }

  const absolutePath = path.resolve(replayPath);
  if (!fs.existsSync(absolutePath)) {
    console.error(`File not found: ${absolutePath}`);
    process.exit(1);
  }

  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: VIEWPORT,
    deviceScaleFactor: DEVICE_SCALE,
    colorScheme: 'light',
  });
  const page = await context.newPage();

  console.log(`Opening ${absolutePath}`);
  await page.goto(`file://${absolutePath}`);
  await page.waitForTimeout(500);

  // 1. Overview
  console.log('Capturing Overview...');
  await page.evaluate(() => showOverview());
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(ASSETS_DIR, 'screenshot-replay.png') });

  // 2. Files
  console.log('Capturing Files...');
  await page.evaluate(() => showFiles());
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(ASSETS_DIR, 'screenshot-replay-files.png') });

  // 3. Phase Detail (pick phase with richest tool data)
  console.log('Capturing Phase Detail (tools)...');
  const bestPhase = await page.evaluate(() => {
    let best = { num: '1', tools: 0 };
    for (const phase of DATA.phases) {
      const count = phase.attempts.reduce((s, a) => s + (a.tools ? a.tools.length : 0), 0);
      if (count > best.tools) best = { num: String(phase.number), tools: count };
    }
    return best.num;
  });
  console.log(`  Best phase: ${bestPhase}`);
  await page.evaluate((num) => showPhaseDetail(num), bestPhase);
  await page.waitForTimeout(300);

  // Expand attempt details to reveal tool breakdown table
  const detailsToggle = await page.$('.attempt-details-toggle');
  if (detailsToggle) {
    await detailsToggle.click();
    await page.waitForTimeout(300);
  }

  // Scroll tool breakdown table into view
  await page.evaluate(() => {
    const table = document.querySelector('.tool-detail-table');
    if (table) table.scrollIntoView({ block: 'start' });
  });
  await page.waitForTimeout(200);
  await page.screenshot({ path: path.join(ASSETS_DIR, 'screenshot-replay-tools.png') });

  // 4. Time Travel (scrub to ~40%)
  console.log('Capturing Time Travel...');
  await page.evaluate(() => showTimeTravel());
  await page.waitForTimeout(500);
  await page.evaluate(() => {
    const slider = document.getElementById('tt-slider');
    if (slider) {
      slider.value = Math.floor(Number(slider.max) * 0.4);
      slider.dispatchEvent(new Event('input'));
    }
  });
  await page.waitForTimeout(300);
  await page.screenshot({ path: path.join(ASSETS_DIR, 'screenshot-replay-timetravel.png') });

  await browser.close();
  console.log('Done! Screenshots saved to assets/');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
