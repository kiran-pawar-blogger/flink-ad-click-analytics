'use strict';

/**
 * Headless browser test: opens the Ad UI, switches through all 5 users,
 * clicks every ad for each user, then polls the Report UI to confirm
 * click data landed in MongoDB via Flink.
 */

const { chromium } = require('playwright');

const AD_UI_URL    = 'http://localhost/ads';
const REPORT_URL   = 'http://localhost/reports';
const API_URL      = 'http://localhost/api/clicks';

const USERS = ['user-alice', 'user-bob', 'user-carol', 'user-dave', 'user-eve'];
// Ad IDs defined in the Ad UI
const AD_IDS = ['ad-001', 'ad-002', 'ad-003', 'ad-004', 'ad-005', 'ad-006'];

async function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page    = await context.newPage();

  // Capture browser console for debugging
  page.on('console', msg => {
    if (msg.type() === 'error') console.log(`  [browser error] ${msg.text()}`);
  });

  // ── 1. Verify Ad UI loads ─────────────────────────────────────────────────
  console.log('\n[1] Opening Ad UI...');
  await page.goto(AD_UI_URL, { waitUntil: 'networkidle', timeout: 15000 });
  const title = await page.title();
  console.log(`    Page title: "${title}"`);

  const adCards = await page.locator('.ad-card').count();
  console.log(`    Ad cards found: ${adCards}`);
  if (adCards === 0) throw new Error('No ad cards rendered — check ingress / ad-ui service');

  // ── 2. Click all ads as all users ─────────────────────────────────────────
  console.log('\n[2] Clicking ads as each user...');

  let totalClicks = 0;

  for (const userId of USERS) {
    // Switch user via the dropdown
    await page.selectOption('#userSelect', userId);
    await sleep(300);

    const currentUser = await page.locator('#current-user').innerText();
    console.log(`\n    User: ${currentUser}`);

    // Click every ad card
    const cards = page.locator('.ad-card');
    const count = await cards.count();

    for (let i = 0; i < count; i++) {
      const card    = cards.nth(i);
      const adTitle = await card.locator('.ad-title').innerText();

      // Intercept the API response
      const [response] = await Promise.all([
        page.waitForResponse(
          r => r.url().includes('/api/clicks') && r.request().method() === 'POST',
          { timeout: 5000 }
        ),
        card.click(),
      ]);

      const status = response.status();
      let body = '';
      try { body = JSON.stringify(await response.json()); } catch (_) {}

      const ok = status === 202 ? 'OK ' : 'ERR';
      console.log(`    [${ok}] ${userId} clicked "${adTitle}" -> HTTP ${status} ${body}`);
      totalClicks++;
      await sleep(150);
    }
  }

  console.log(`\n    Total clicks fired: ${totalClicks}`);

  // ── 3. Verify click API directly ─────────────────────────────────────────
  console.log('\n[3] Smoke-testing Click API directly...');
  const apiPage = await context.newPage();
  const apiRes  = await apiPage.request.post(API_URL, {
    data: {
      userId: 'user-test',
      adId:   'ad-001',
      adName: 'Direct API Test',
    },
    headers: { 'Content-Type': 'application/json' },
  });
  console.log(`    Direct POST /api/clicks -> HTTP ${apiRes.status()}`);
  const apiBody = await apiRes.json();
  console.log(`    Response: ${JSON.stringify(apiBody)}`);
  await apiPage.close();

  // ── 4. Poll Report API for data (Flink window = 60s) ─────────────────────
  console.log('\n[4] Waiting up to 90s for Flink to aggregate and write to MongoDB...');

  const reportPage = await context.newPage();
  let found = false;

  for (let attempt = 1; attempt <= 18; attempt++) {
    await sleep(5000);
    try {
      const res  = await reportPage.request.get('http://localhost/reports/api/reports/per-user-per-ad');
      const data = await res.json();

      if (Array.isArray(data) && data.length > 0) {
        console.log(`\n    [attempt ${attempt}] Data arrived in MongoDB!`);
        console.log(`    Records: ${data.length}`);
        console.log('\n    Sample records (userId | adId | clicks):');
        data.slice(0, 10).forEach(r => {
          console.log(`      ${r.userId.padEnd(14)} | ${r.adId.padEnd(7)} | ${r.totalClicks} clicks`);
        });
        found = true;
        break;
      } else {
        process.stdout.write(`    [attempt ${attempt}] No data yet (${5 * attempt}s elapsed)...\r`);
      }
    } catch (e) {
      console.log(`    [attempt ${attempt}] Report API error: ${e.message}`);
    }
  }

  if (!found) {
    console.log('\n    No aggregated data after 90s.');
    console.log('    Flink window may not have closed yet — check: kubectl logs -n ad-analytics deployment/flink-jobmanager');
  }

  await reportPage.close();
  await browser.close();

  console.log('\n[done]');
  process.exit(found ? 0 : 1);
})();
