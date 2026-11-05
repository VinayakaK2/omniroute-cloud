const fsp = require('node:fs/promises');
const fs = require('node:fs');

function shouldBlock(p) {
  if (typeof p !== 'string') return false;
  return p.includes('cgroup') || p.includes('/proc/pressure');
}

const origFspReadFile = fsp.readFile;
fsp.readFile = async function (path, ...args) {
  if (shouldBlock(path)) {
    const err = new Error(`ENOENT: no such file or directory, open '${path}'`);
    err.code = 'ENOENT';
    throw err;
  }
  return origFspReadFile.apply(this, [path, ...args]);
};

const origFsReadFile = fs.readFile;
fs.readFile = function (path, ...args) {
  if (shouldBlock(path)) {
    const cb = typeof args[args.length - 1] === 'function' ? args[args.length - 1] : null;
    const err = new Error(`ENOENT: no such file or directory, open '${path}'`);
    err.code = 'ENOENT';
    if (cb) {
      setImmediate(() => cb(err));
      return;
    }
  }
  return origFsReadFile.apply(this, [path, ...args]);
};

console.log('[Patch] 512MB container environment: cgroup/host PSI ratio checks bypassed. V8 heap guard remains active.');
