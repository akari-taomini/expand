'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'tavern-memory.cjs'), 'utf8');
const delimiter = 'TAVERN_MEMORY_NODE_SOURCE_END';
if (source.split('\n').includes(delimiter)) throw new Error('Heredoc delimiter conflicts with source.');
const header = `#!/usr/bin/env bash
set -euo pipefail
if ! command -v node >/dev/null 2>&1; then
  echo '找不到 Node.js，请先确认当前 Termux 中的酒馆可以正常启动。' >&2
  exit 1
fi
task_file=$(mktemp "\${TMPDIR:-/tmp}/tavern-memory.XXXXXXXX.cjs")
trap 'rm -f -- "$task_file"' EXIT
cat > "$task_file" <<'${delimiter}'
`;
fs.writeFileSync(path.join(root, 'install.sh'), header + source + '\n' + delimiter + '\nnode "$task_file" "$@"\n', {mode:0o755});
console.log('Generated install.sh');
