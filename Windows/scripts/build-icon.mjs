import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.dirname(scriptDirectory);
const source = path.resolve(projectDirectory, '..', 'design', 'AppIcon-master.png');
const assetsDirectory = path.join(projectDirectory, 'assets');
const pngOutput = path.join(assetsDirectory, 'AppIcon.png');
const icoOutput = path.join(assetsDirectory, 'AppIcon.ico');
const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'file-desensitizer-icon-'));
const sizes = [16, 32, 48, 64, 128, 256];

fs.mkdirSync(assetsDirectory, { recursive: true });
fs.copyFileSync(source, pngOutput);

try {
  const images = sizes.map((size) => {
    const output = path.join(temporaryDirectory, `icon-${size}.png`);
    execFileSync('/usr/bin/sips', ['-z', String(size), String(size), source, '--out', output], {
      stdio: 'ignore'
    });
    return { size, data: fs.readFileSync(output) };
  });

  const headerSize = 6 + (images.length * 16);
  const header = Buffer.alloc(headerSize);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  let offset = headerSize;
  images.forEach(({ size, data }, index) => {
    const entry = 6 + (index * 16);
    header.writeUInt8(size === 256 ? 0 : size, entry);
    header.writeUInt8(size === 256 ? 0 : size, entry + 1);
    header.writeUInt8(0, entry + 2);
    header.writeUInt8(0, entry + 3);
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(data.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += data.length;
  });
  fs.writeFileSync(icoOutput, Buffer.concat([header, ...images.map(({ data }) => data)]));
  console.log(`Windows icon created: ${icoOutput}`);
} finally {
  fs.rmSync(temporaryDirectory, { recursive: true, force: true });
}
