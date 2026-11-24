import { readdirSync, readFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

// Browser libraries explicitly declare their platform so native Flutter runs
// exclude them. Discover that declaration instead of maintaining a second list.
export function discoverWebTests(packageDirectory) {
  const worker = [];
  const browser = [];
  function visit(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory()) {
        visit(path);
      } else if (entry.isFile()) {
        const name = relative(packageDirectory, path).replaceAll('\\', '/');
        if (entry.name.endsWith('_test.cjs')) worker.push(name);
        if (entry.name.endsWith('_test.dart')) {
          const source = readFileSync(path, 'utf8');
          if (/^\s*@TestOn\(\s*(['"])browser\1\s*\)/m.test(source)) browser.push(name);
        }
      }
    }
  }
  visit(resolve(packageDirectory, 'test'));
  return { worker: worker.sort(), browser: browser.sort() };
}

function main(arguments_) {
  const [suite, option] = arguments_;
  if (!['worker', 'browser'].includes(suite) || (option && option !== '--list') || arguments_.length > 2) {
    throw new Error('Usage: node .github/scripts/web-tests.mjs <worker|browser> [--list]');
  }
  const packageDirectory = resolve(repository, 'packages/pdfrx');
  const files = discoverWebTests(packageDirectory)[suite];
  if (!files.length) throw new Error(`No ${suite} tests discovered; refusing an empty CI gate.`);
  if (option === '--list') {
    console.log(JSON.stringify(files, null, 2));
    return;
  }
  console.log(`Discovered ${files.length} ${suite} test files:\n${files.join('\n')}`);
  const command = suite === 'worker' ? process.execPath : 'flutter';
  const args = suite === 'worker'
    ? ['--test', ...files]
    : ['test', '--platform', 'chrome', '--concurrency=1', ...files];
  const result = spawnSync(command, args, { cwd: packageDirectory, stdio: 'inherit' });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv.slice(2));
}
