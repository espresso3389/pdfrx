import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { discoverWebTests } from './web-tests.mjs';

test('new worker and browser regressions enter their gate without a workflow list edit', (context) => {
  const packageDirectory = mkdtempSync(join(tmpdir(), 'pdfrx-ci-discovery-'));
  context.after(() => rmSync(packageDirectory, { recursive: true, force: true }));
  const fixtures = {
    'worker_test.cjs': '',
    'nested/new_lifetime_test.cjs': '',
    'nested/new bridge_test.dart': '@TestOn("browser")\nlibrary;\n',
    'render_test.dart': "// Platform declaration\n@TestOn('browser')\nlibrary;\n",
    'native_test.dart': "import 'dart:io';\n",
    'helper.dart': "@TestOn('browser')\nlibrary;\n",
    'helper.cjs': '',
  };
  for (const [name, source] of Object.entries(fixtures)) {
    const file = join(packageDirectory, 'test', name);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, source);
  }
  assert.deepEqual(discoverWebTests(packageDirectory), {
    worker: ['test/nested/new_lifetime_test.cjs', 'test/worker_test.cjs'],
    browser: ['test/nested/new bridge_test.dart', 'test/render_test.dart'],
  });
});
