# 酒馆内存上限工具

用于安卓 Termux 中的 SillyTavern。修改 start.sh 中 Node.js 的 `--max-old-space-size`，自动生成备份，并可恢复。无需 root，无需安装 npm 包。

这项设置提高 V8 old space 的内存上限，不增加手机物理内存或存储空间。8192 MiB 不是适合所有手机的默认值。请为系统、浏览器和其他应用留出内存。设置过高可能导致酒馆被系统终止。

## 一条命令运行

在 Termux 中粘贴：

```bash
curl -fsSL --connect-timeout 15 --max-time 120 https://raw.githubusercontent.com/akari-taomini/expand/main/install.sh -o "$HOME/tavern-memory.sh" && bash "$HOME/tavern-memory.sh"
```

脚本下载成功后才会运行。它会寻找当前目录及家目录下常见的 SillyTavern 安装位置，询问安装路径并检查读写权限，再显示以下选项：

| 输入编号 | 内存上限 |
| --- | --- |
| 1 | 2048 MiB |
| 2 | 4096 MiB |
| 3 | 8192 MiB |
| 4 | 16384 MiB |

输入编号后，脚本会预览改动，要求输入 `y` 确认，然后自动备份并修改。选项表示 Node.js 内存上限，不代表手机一定能提供这些内存。

下载的入口文件会保留在家目录，方便下次运行：

```bash
bash "$HOME/tavern-memory.sh"
```

脚本运行完后，在原先运行酒馆的终端按 Ctrl+C 停止酒馆，再用 `bash start.sh` 启动。修改只对新进程生效；脚本不会自动结束正在运行的酒馆。

如果提示找不到 Node.js，请先确认 Termux 里的酒馆已经能正常启动。如果提示找不到 curl，可先运行 `pkg install curl`。若 GitHub 下载失败，请检查网络后重试。

## 指定参数运行

4096 是演示值，请根据自己的手机内存选择。

```bash
bash "$HOME/tavern-memory.sh" --dir ~/SillyTavern --size 4096 --dry-run
bash "$HOME/tavern-memory.sh" --dir ~/SillyTavern --size 4096
```

`--dry-run` 只预览，不写入文件。已有相同上限时不会重复修改。

## 恢复

终端会显示修改前备份的完整路径。替换下面的示例路径后运行，再重新启动酒馆：

```bash
bash "$HOME/tavern-memory.sh" --dir ~/SillyTavern --restore "/实际酒馆目录/start.sh.memory-backup-实际后缀"
```

恢复也会先备份当前文件。酒馆升级可能覆盖 start.sh，升级后可重新运行工具。

## 支持的启动格式

目录中需要存在普通文件 start.sh 和 server.js，且有且只有一条以下形式的启动命令：

```bash
node "server.js" "$@"
node --max-old-space-size=4096 "server.js" "$@"
```

支持前置 `exec`、`./server.js`、单引号、CRLF 换行和行尾注释。保留文件权限和其他行，不依赖固定行号。不支持自定义额外 Node.js 参数、多行启动命令、符号链接文件或不使用 start.sh 的启动器；遇到这些情况会提示并停止。

## 维护

install.sh 内嵌 tavern-memory.cjs，因此一键运行只下载一个文件。修改核心脚本后，在仓库根目录运行 `node scripts/build-installer.cjs` 重新生成入口，并运行 `node --check tavern-memory.cjs`、`node tests/memory.cjs` 和 `bash -n install.sh` 检查。

当前已验证电脑临时样例中的预览、修改、备份、恢复、重复运行、换行保留和不支持格式的拒绝行为，尚未在真实手机上实测。

Node.js 参数说明：[官方文档](https://nodejs.org/api/cli.html#--max-old-space-sizesize-in-mib)。
