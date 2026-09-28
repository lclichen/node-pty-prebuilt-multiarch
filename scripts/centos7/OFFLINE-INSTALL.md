# node-pty CentOS 7 离线安装说明

本压缩包内的二进制是在 glibc 2.17（与 CentOS 7 完全一致）的容器环境中编译，
并通过了符号版本检查（`GLIBC <= 2.17`、`GLIBCXX <= 3.4.19`）和真实 pty 冒烟测试。

二进制以纯 N-API（`node-addon-api`，NAPI 8）方式构建：**同一个 `.node` 文件可以在
Node 16 及以上的任意版本加载**，与具体 ABI 无关。`prebuilds/linux-x64/` 下按常见
Node 版本预置了多个 ABI 文件名（`node.abi93.node`、`node.abi115.node` 等），
它们内容相同，只是文件名不同，目的是让运行时加载器
（`lib/prebuild-file-path.ts` 编译产物）总能按当前 Node 的 ABI 找到文件。

## 快速路径：内网已装 unofficial glibc-217 的 Node 22，只需替换二进制

若内网机器已运行 unofficial glibc-217 构建的 Node 22（ABI = 127），
且项目其余部分都已验证可用，则只需把编译产物放进**已安装的包目录**，
完全不需要编译器，也不需要动项目的其它内容：

```bash
node -p process.versions.modules        # 应输出 127（Node 22）

# 进入已安装的 @homebridge/node-pty-prebuilt-multiarch 包目录（package.json 所在处），
# 即 <你的项目>/node_modules/@homebridge/node-pty-prebuilt-multiarch
mkdir -p prebuilds/linux-x64
cp /path/to/node.abi127.node prebuilds/linux-x64/

# 防御性清理：加载器优先读 prebuilds/，其次才落到 build/Release/pty.node。
# 若之前下载/编译过不兼容的旧二进制，删掉以免将来回退到坏文件。
rm -f build/Release/pty.node
```

完成后按「三、验证」测试。如果 `process.versions.modules` 输出的不是 127，
把 `node.abi127.node` 复制改名为 `node.abi<该数字>.node` 即可（N-API 二进制跨 ABI 通用）。

## 一、准备内网机器的 Node.js（关键前提）

CentOS 7 的 glibc 是 2.17，而 Node 18 以后的官方构建要求 glibc >= 2.28，
**官方 tar 包在 CentOS 7 上会直接报 `GLIBC_2.28 not found` 而无法运行**。可选：

1. **推荐：Node.js 非官方 glibc-217 构建（支持 v18–v23，即 18/20/22 可用）**
   在外网下载后拷入内网安装：
   ```
   https://unofficial-builds.nodejs.org/download/release/v22.23.0/node-v22.23.0-linux-x64-glibc-217.tar.gz
   https://unofficial-builds.nodejs.org/download/release/v20.18.1/node-v20.18.1-linux-x64-glibc-217.tar.gz
   ```
   ```bash
   tar -xzf node-v22.23.0-linux-x64-glibc-217.tar.gz -C /usr/local --strip-components=1
   node -v   # 应正常输出版本号
   ```

2. **备选：官方 Node 16（最后一个官方支持 glibc 2.17 的大版本）**
   ```
   https://nodejs.org/dist/v16.20.2/node-v16.20.2-linux-x64.tar.gz
   ```
   注意：本包 `package.json` 的 `engines` 声明 `>=20`，npm 安装时会有警告；
   JS 产物本身编译为 ES5，Node 16 大概率可用，但请用下方验证命令实测。

## 二、安装方式

### 方式 A：作为 node_modules 中的包直接使用（推荐）

1. 解压主压缩包：
   ```bash
   tar -xzf node-pty-prebuilt-multiarch-centos7-linux-x64.tar.gz
   ```
2. 放入你项目的依赖目录，**目录名必须是完整包名**：
   ```bash
   mkdir -p <你的项目>/node_modules/@homebridge
   cp -r node-pty-prebuilt-multiarch-centos7 \
         <你的项目>/node_modules/@homebridge/node-pty-prebuilt-multiarch
   ```
3. 在你项目的 `package.json` 的 `dependencies` 中声明（版本与包内一致，例如）：
   ```json
   "@homebridge/node-pty-prebuilt-multiarch": "0.14.1"
   ```
   这样 npm 之后安装其它依赖时不会把它移除。本包运行时零外部依赖
   （`prebuild-install`、`node-addon-api` 只在编译期/install 脚本中使用），
   内网无 registry 也不影响运行。

### 方式 B：给一台已经装过（但编译失败）的机器补二进制

如果内网机器上已经存在这个包（比如之前 `npm install` 失败留下的半成品），
只需把预编译文件复制过去，完全不需要编译器：

```bash
# 在包根目录下（package.json 所在目录）
mkdir -p prebuilds/linux-x64 build/Release
cp /path/to/prebuilds/linux-x64/*.node prebuilds/linux-x64/
# build/Release 是加载器的兜底路径（优先级低于 prebuilds/），也放一份最保险
cp /path/to/build/Release/pty.node build/Release/   # 若有单独的 pty.node
# lib/ 若不存在（git 克隆的源码），把压缩包里的 lib/ 一并复制过来
```

### 方式 C：不走 node_modules，直接 require 目录

```js
const pty = require('/opt/node-pty-prebuilt-multiarch-centos7');
```

## 三、验证

```bash
node -e "const pty=require('@homebridge/node-pty-prebuilt-multiarch'); \
const p=pty.spawn('/bin/sh',[],{name:'xterm',cols:80,rows:24}); \
console.log('pty ok, pid='+p.pid); p.kill();"
```

输出 `pty ok, pid=...` 即安装成功。

## 四、故障排查

- **`version 'GLIBC_2.xx' not found`**：加载到了别的 `.node`（比如上游 npm 包
  自带的、在新 Debian 上编译的二进制）。确认 `require.resolve` 指向本包目录，
  并删除其 `build/Release` 下旧的 `pty.node` 后替换为本包文件。
- **报 ABI / `was compiled against a different Node.js version`**：
  查看 `node -p process.versions.modules`，在 `prebuilds/linux-x64/` 下若没有
  `node.abi<该数字>.node`，任选一个已有文件复制并改名为该数字即可
  （N-API 二进制跨 ABI 通用，此操作安全）。
- **npm 安装时尝试联网**：内网机器请用上面的方式 A/B 手工放置文件，不要在
  内网跑 `npm install`（它需要访问 registry 下载依赖，且可能尝试从 GitHub
  下载不适配的预编译包）。

## 五、重新构建（外网）

本压缩包由 GitHub Actions（`.github/workflows/centos7-prebuild.yml`）产出，
也可在任何装有 Docker 的 Linux 机器上手工构建：

```bash
git clone https://github.com/lclichen/node-pty-prebuilt-multiarch.git
cd node-pty-prebuilt-multiarch
bash scripts/centos7/build.sh          # 默认 Node 22.23.0
NODE_VERSION=20.18.1 bash scripts/centos7/build.sh
```
