import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { packager } from '@electron/packager';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(scriptDirectory, '..');
const outputDirectory = path.join(projectDirectory, 'out');
const distributionDirectory = path.resolve(projectDirectory, '..', 'dist');
const version = '1.0.0';
const archiveName = `FileDesensitizer-${version}-Windows-x64.zip`;
const archivePath = path.join(distributionDirectory, archiveName);
const checksumPath = `${archivePath}.sha256`;

fs.mkdirSync(distributionDirectory, { recursive: true });

const packagePaths = await packager({
  dir: projectDirectory,
  name: 'FileDesensitizer',
  executableName: 'FileDesensitizer',
  platform: 'win32',
  arch: 'x64',
  out: outputDirectory,
  overwrite: true,
  asar: true,
  prune: true,
  icon: path.join(projectDirectory, 'assets', 'AppIcon.ico'),
  appVersion: version,
  appCopyright: 'Copyright © 2026 FileDesensitizer',
  win32metadata: {
    CompanyName: 'FileDesensitizer',
    FileDescription: 'Excel 文件脱敏与恢复工具',
    ProductName: '文件脱敏工具',
    InternalName: 'FileDesensitizer',
    OriginalFilename: 'FileDesensitizer.exe',
    'requested-execution-level': 'asInvoker'
  },
  ignore: [
    /^\/(?:out|dist|tests)(?:\/|$)/,
    /^\/scripts(?:\/|$)/,
    /^\/assets\/AppIcon\.png$/,
    /^\/\.gitignore$/
  ]
});

if (packagePaths.length !== 1) {
  throw new Error(`预期生成 1 个应用目录，实际生成 ${packagePaths.length} 个`);
}

const packagedDirectory = packagePaths[0];
fs.copyFileSync(
  path.join(projectDirectory, 'README-Windows.txt'),
  path.join(packagedDirectory, 'README-Windows.txt')
);

fs.rmSync(archivePath, { force: true });
fs.rmSync(checksumPath, { force: true });

execFileSync('/usr/bin/zip', [
  '-r',
  '-q',
  archivePath,
  path.basename(packagedDirectory)
], {
  cwd: path.dirname(packagedDirectory),
  stdio: 'inherit'
});

const digest = createHash('sha256')
  .update(fs.readFileSync(archivePath))
  .digest('hex');
fs.writeFileSync(checksumPath, `${digest}  ${archiveName}\n`, 'utf8');

const sizeMiB = (fs.statSync(archivePath).size / 1024 / 1024).toFixed(1);
console.log(`Windows 应用目录：${packagedDirectory}`);
console.log(`分发包：${archivePath} (${sizeMiB} MiB)`);
console.log(`SHA-256：${digest}`);
