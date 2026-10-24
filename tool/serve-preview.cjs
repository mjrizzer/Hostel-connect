const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../build/web');
const types = {'.html':'text/html', '.js':'text/javascript', '.json':'application/json', '.css':'text/css', '.wasm':'application/wasm', '.png':'image/png', '.ttf':'font/ttf'};
http.createServer((req, res) => {
  let requested;
  try { requested = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch {res.writeHead(400).end();return;}
  const target=path.resolve(root, '.'+requested);
  if(!target.startsWith(root+path.sep) && target!==root){res.writeHead(403).end();return;}
  const file=fs.existsSync(target)&&fs.statSync(target).isFile()?target:path.join(root,'index.html');
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control','no-store');
  fs.createReadStream(file).pipe(res);
}).listen(4173, '127.0.0.1',()=>console.log('Hostel Connect preview: http://127.0.0.1:4173'));
