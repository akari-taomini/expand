#!/usr/bin/env bash
set -euo pipefail
if ! command -v node >/dev/null 2>&1; then
  echo '找不到 Node.js，请先确认当前 Termux 中的酒馆可以正常启动。' >&2
  exit 1
fi
task_file=$(mktemp "${TMPDIR:-/tmp}/tavern-memory.XXXXXXXX.cjs")
trap 'rm -f -- "$task_file"' EXIT
cat > "$task_file" <<'TAVERN_MEMORY_NODE_SOURCE_END'
#!/usr/bin/env node
'use strict';

// No packages required. Run with the Node.js already used by SillyTavern.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const readline = require('node:readline');

const palette = { title: '1;35', info: '36', success: '1;32', warning: '1;33', error: '1;31', strong: '1;37', muted: '90' };
function color(kind, text, stream = process.stdout) {
  if (!stream.isTTY || process.env.NO_COLOR !== undefined || process.env.TERM === 'dumb') return text;
  return `\x1b[${palette[kind]}m${text}\x1b[0m`;
}
function section(text) { console.log(`\n${color('title', `── ${text} ──`)}`); }

function fail(message) { throw new Error(message); }
function usage() {
  console.log(`${color('title', '酒馆 Node.js 内存上限修改工具')}
用法：
  node tavern-memory.cjs --dir ~/SillyTavern --size 4096 --dry-run
  node tavern-memory.cjs --dir ~/SillyTavern --size 4096
  node tavern-memory.cjs --dir ~/SillyTavern --restore "备份文件完整路径"

--dir      酒馆目录，省略时使用当前目录
--size     old space 上限，单位 MiB，必须显式指定
--dry-run  只预览，不写文件；也可用于预览恢复
--restore  恢复本工具在同一目录生成的备份
--help     显示帮助

修改后需要停止酒馆进程，再用 start.sh 启动。`);
}

function parse(args) {
  const result = { dir: process.cwd(), dryRun: false };
  const seen = new Set();
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    if (seen.has(key)) fail(`重复参数：${key}`);
    seen.add(key);
    if (key === '--help') { result.help = true; continue; }
    if (key === '--dry-run') { result.dryRun = true; continue; }
    if (!['--dir', '--size', '--restore'].includes(key)) fail(`未知参数：${key}`);
    const value = args[++i];
    if (!value || value.startsWith('--')) fail(`${key} 缺少值`);
    result[key.slice(2)] = value;
  }
  if (result.help) return result;
  if (Boolean(result.size) === Boolean(result.restore)) fail('请在 --size 和 --restore 中指定且只指定一个。');
  if (result.size && (!/^[1-9]\d*$/.test(result.size) || Number(result.size) < 128 || Number(result.size) > 65536)) {
    fail('--size 必须是 128 到 65536 之间的整数，单位 MiB。');
  }
  return result;
}

function readRegular(file) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) fail(`仅支持普通文件：${file}`);
  return { bytes: fs.readFileSync(file), mode: stat.mode & 0o777 };
}

function save(file, original, updated, mode) {
  const suffix = `${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomBytes(4).toString('hex')}`;
  const backup = `${file}.memory-backup-${suffix}`;
  const temp = `${file}.memory-temp-${suffix}`;
  // Keep a recoverable copy before replacing anything.
  fs.writeFileSync(backup, original, { flag: 'wx', mode });
  try {
    fs.writeFileSync(temp, updated, { flag: 'wx', mode });
    fs.chmodSync(temp, mode);
    if (!fs.readFileSync(file).equals(original)) fail('start.sh 在操作期间发生变化，已取消写入。');
    fs.renameSync(temp, file);
  } finally {
    if (fs.existsSync(temp)) fs.unlinkSync(temp);
  }
  console.log(color('success', `已保存：${file}`));
  console.log(`${color('info', '修改前备份：')}\n${color('strong', backup)}`);
  console.log(color('warning', '下一步：停止正在运行的酒馆，再通过 start.sh 启动后生效。'));
}

async function interactive() {
  if (!process.stdin.isTTY) fail('交互模式需要终端输入；请下载脚本后运行 node，或显式传入 --dir 和 --size。');
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = (question) => new Promise(resolve => rl.question(question, resolve));
  rl.on('SIGINT', () => { rl.close(); process.exit(130); });
  try {
    section('酒馆内存上限设置');
    console.log(color('info', '修改 start.sh · 自动备份 · 支持恢复'));
    console.log(color('warning', '注意：调整的是 Node.js 内存上限，不会增加手机物理内存。'));
    section('1 / 3 选择酒馆目录');
    const candidates = [...new Set([process.cwd(), path.join(os.homedir(), 'SillyTavern'), path.join(os.homedir(), 'sillytavern'), path.join(os.homedir(), 'Silly Tavern')])];
    const found = candidates.filter(dir => fs.existsSync(path.join(dir, 'start.sh')) && fs.existsSync(path.join(dir, 'server.js')));
    const suggested = found.length === 1 ? found[0] : '';
    if (found.length > 1) console.log(color('info', `找到多个目录，请选择你的酒馆目录：\n${found.join('\n')}`));
    if (suggested) console.log(`${color('info', '检测到目录：')}\n${color('strong', suggested)}`);
    const answer = (await ask(color('info', `酒馆目录${suggested ? ' [回车使用检测到的目录]' : '（完整路径）'}：`))).trim();
    let dir = answer || suggested;
    if (dir === '~') dir = os.homedir();
    if (dir.startsWith('~/')) dir = path.join(os.homedir(), dir.slice(2));
    if (!dir) fail('没有指定酒馆目录。');
    dir = fs.realpathSync(path.resolve(dir));
    const startFile = path.join(dir, 'start.sh');
    readRegular(startFile);
    readRegular(path.join(dir, 'server.js'));
    try {
      fs.accessSync(startFile, fs.constants.R_OK | fs.constants.W_OK);
      fs.accessSync(dir, fs.constants.R_OK | fs.constants.W_OK | fs.constants.X_OK);
    } catch {
      fail('当前 Termux 没有读写酒馆目录或 start.sh 的权限，请使用安装酒馆的 Termux 运行。');
    }
    console.log(color('success', '权限检查通过：目录和 start.sh 可读写。'));
    section('2 / 3 选择内存上限');
    console.log(`系统报告总内存：${color('strong', `${Math.floor(os.totalmem() / 1024 / 1024)} MiB`)}`);
    console.log(color('warning', '请给安卓系统和其他应用留出余量，数值越大不代表越流畅。'));
    console.log([
      color('success', '  [1]   2048 MiB'),
      color('info',    '  [2]   4096 MiB'),
      color('warning', '  [3]   8192 MiB'),
      color('title',   '  [4]  16384 MiB'),
    ].join('\n'));
    const sizes = { '1': '2048', '2': '4096', '3': '8192', '4': '16384' };
    let choice;
    do {
      choice = (await ask(color('strong', '输入编号 1 / 2 / 3 / 4：'))).trim();
      if (!sizes[choice]) console.log(color('error', '无效选项：请输入 1、2、3 或 4。'));
    } while (!sizes[choice]);
    const size = sizes[choice];
    console.log(color('success', `已选择：${size} MiB`));
    section('3 / 3 预览并确认');
    const options = parse(['--dir', dir, '--size', size]);
    // Validate the target and show the exact change before asking to write it.
    await main({ ...options, dryRun: true });
    const confirm = (await ask(color('warning', '应用以上设置？输入 y 确认，其他输入取消：'))).trim().toLowerCase();
    if (confirm !== 'y') { console.log(color('info', '已取消，没有写文件。')); return null; }
    return options;
  } finally { rl.close(); }
}

async function main(supplied) {
  const options = supplied || (process.argv.length === 2 ? await interactive() : parse(process.argv.slice(2)));
  if (!options) return;
  if (options.help) return usage();
  const dir = fs.realpathSync(path.resolve(options.dir));
  const file = path.join(dir, 'start.sh');
  const original = readRegular(file);
  if (options.restore) {
    const backup = path.resolve(options.restore);
    if (fs.realpathSync(path.dirname(backup)) !== dir || !/^start\.sh\.memory-backup-[0-9TZ-]+-[0-9a-f]{8}$/.test(path.basename(backup))) {
      fail('恢复来源必须是当前酒馆目录中本工具生成的 start.sh 备份。');
    }
    const source = readRegular(backup);
    if (source.bytes.equals(original.bytes)) return console.log(color('success', '当前文件与备份一致，无需恢复。'));
    if (options.dryRun) return console.log(color('info', `将用以下备份恢复 start.sh：${backup}\n仅预览，没有写文件。`));
    save(file, original.bytes, source.bytes, original.mode);
    return;
  }
  readRegular(path.join(dir, 'server.js'));
  const size = Number(options.size);
  if (!['x64', 'arm64', 'ppc64', 's390x', 'riscv64', 'loong64'].includes(process.arch) && size > 2048) {
    fail(`当前 Node.js 架构为 ${process.arch}；此工具不对该架构设置超过 2048 MiB 的上限。`);
  }
  const total = Math.floor(os.totalmem() / 1024 / 1024);
  console.log(color('muted', `Node.js 架构：${process.arch}；系统报告总内存：${total} MiB`));
  if (size > total / 2) console.log(color('warning', '内存提醒：设置值超过总内存的一半，请确认系统和其他应用有足够余量。'));
  const text = original.bytes.toString('utf8');
  if (!Buffer.from(text, 'utf8').equals(original.bytes)) fail('start.sh 不是有效 UTF-8 文本，未修改。');
  const lines = text.split('\n');
  // Only recognize the tutorial's simple launch command. Preserve all other lines.
  const command = /^([ \t]*(?:exec[ \t]+)?node[ \t]+)(?:(--max[-_]old[-_]space[-_]size)=([0-9]+)[ \t]+)?((?:"(?:\.\/)?server\.js"|'(?:\.\/)?server\.js'|(?:\.\/)?server\.js)[ \t]+(?:"\$@"|\$@)(?:[ \t]+#.*)?[ \t]*)(\r?)$/;
  const matches = [];
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(command);
    if (match) matches.push({ index: i, match });
  }
  if (matches.length !== 1) fail(`找到 ${matches.length} 条符合教程格式的启动命令，需要恰好一条。请提供你的 start.sh 内容以适配，文件未修改。`);
  const { index, match } = matches[0];
  const next = `${match[1]}--max-old-space-size=${size} ${match[4]}${match[5]}`;
  console.log(`${color('muted', '修改前：')}\n${color('muted', lines[index].replace(/\r$/, ''))}`);
  console.log(`${color('success', '修改后：')}\n${color('success', next.replace(/\r$/, ''))}`);
  if (Number(match[3]) === size) return console.log(color('success', '已有相同上限，无需修改。'));
  if (options.dryRun) return console.log(color('info', '仅预览，没有写文件。'));
  lines[index] = next;
  save(file, original.bytes, Buffer.from(lines.join('\n'), 'utf8'), original.mode);
}

main().catch(error => {
  console.error(color('error', `失败：${error.message}`, process.stderr));
  process.exitCode = 1;
});

TAVERN_MEMORY_NODE_SOURCE_END
node "$task_file" "$@"
