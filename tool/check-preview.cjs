const { chromium }=require('../.tools/preview-browser/node_modules/playwright');
(async()=>{
  const browser=await chromium.launch({channel:'chrome',headless:true});
  const page=await browser.newPage({viewport:{width:430,height:932},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(e.stack||e.message));
  page.on('console',m=>console.log(m.type()+': '+m.text()));
  page.on('requestfailed',r=>console.log('Request failed: '+r.url()+' '+r.failure()?.errorText));
  await page.goto('http://127.0.0.1:4173');
  await page.waitForTimeout(12000);
  await page.screenshot({path:'docs/preview-home.png'});
  await page.goto('http://127.0.0.1:4173/#/laundry');
  await page.waitForTimeout(2500);
  await page.screenshot({path:'docs/preview-laundry.png'});
  console.log(JSON.stringify({errors,title:await page.title()}));
  await browser.close();
  if(errors.length)process.exitCode=1;
})();
