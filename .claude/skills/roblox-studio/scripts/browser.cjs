#!/usr/bin/env node
// Drive the container's Chromium (started by start_browser.sh with
// --remote-debugging-port=9222) over CDP. Used for Roblox sign-up / sign-in,
// since the OAuth redirect must land inside the container.
//
//   browser.cjs goto <url>                 navigate the active tab
//   browser.cjs shot <file.png> [scale]     screenshot the active tab
//   browser.cjs text                        visible text of the page
//   browser.cjs click <selector|text=...>   click an element
//   browser.cjs fill <selector> <value>     type into an input
//   browser.cjs select <selector> <value>   choose a <select> option
//   browser.cjs eval <js>                   evaluate JS, print JSON result
//   browser.cjs url                         print the active tab URL
const { chromium } = require(
  require("child_process").execSync("npm root -g").toString().trim() + "/playwright"
);

(async () => {
  const [cmd, ...args] = process.argv.slice(2);
  const browser = await chromium.connectOverCDP("http://127.0.0.1:9222");
  const ctx = browser.contexts()[0];
  let page = ctx.pages().filter((p) => !p.url().startsWith("devtools:")).pop();
  if (!page) page = await ctx.newPage();
  await page.bringToFront();
  try {
    switch (cmd) {
      case "goto":
        await page.goto(args[0], { waitUntil: "domcontentloaded", timeout: 60000 });
        await page.waitForTimeout(2000);
        console.log(page.url());
        break;
      case "shot":
        await page.screenshot({ path: args[0], scale: "css" });
        console.log(args[0]);
        break;
      case "text":
        console.log(await page.evaluate(() => document.body.innerText));
        break;
      case "click":
        await page.locator(args[0]).first().click({ timeout: 15000 });
        await page.waitForTimeout(1500);
        console.log("clicked", page.url());
        break;
      case "fill":
        await page.locator(args[0]).first().fill(args[1], { timeout: 15000 });
        console.log("filled");
        break;
      case "select":
        console.log(await page.locator(args[0]).first().selectOption(args[1]));
        break;
      case "eval":
        console.log(JSON.stringify(await page.evaluate(args[0]), null, 1));
        break;
      case "url":
        console.log(page.url());
        break;
      default:
        console.error("unknown command", cmd);
        process.exitCode = 2;
    }
  } finally {
    // Disconnect without closing the shared browser.
    await browser.close().catch(() => {});
  }
})().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
