const fs = require('node:fs');
const path = require('node:path');
const { app, BrowserWindow, dialog, ipcMain, shell } = require('electron');
const {
  analyzeWorkbook,
  desensitizeWorkbook,
  outputNames,
  recoverWorkbook
} = require('./core/workbook');

const trustedFiles = new Set();

function requireTrustedFile(filePath) {
  if (!trustedFiles.has(path.resolve(filePath))) throw new Error('请通过软件重新选择该文件');
}

async function confirmOverwrite(filePaths) {
  const existingFiles = filePaths.filter((filePath) => fs.existsSync(filePath));
  if (!existingFiles.length) return true;
  const result = await dialog.showMessageBox({
    type: 'warning',
    title: '文件已存在',
    message: '以下文件已存在：',
    detail: `${existingFiles.map((filePath) => path.basename(filePath)).join('\n')}\n\n是否覆盖？`,
    buttons: ['取消', '覆盖'],
    defaultId: 0,
    cancelId: 0,
    noLink: true
  });
  return result.response === 1;
}

function createWindow() {
  const window = new BrowserWindow({
    width: 1120,
    height: 760,
    minWidth: 920,
    minHeight: 620,
    title: '文件脱敏工具',
    icon: path.join(__dirname, 'assets', 'AppIcon.ico'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  window.setMenuBarVisibility(false);
  window.loadFile(path.join(__dirname, 'src', 'index.html'));
}

ipcMain.handle('pick-xlsx', async () => {
  const result = await dialog.showOpenDialog({
    title: '选择 Excel 文件',
    properties: ['openFile'],
    filters: [{ name: 'Excel 工作簿', extensions: ['xlsx'] }]
  });
  if (result.canceled || !result.filePaths[0]) return null;
  const filePath = path.resolve(result.filePaths[0]);
  trustedFiles.add(filePath);
  return { path: filePath, name: path.basename(filePath) };
});

ipcMain.handle('analyze-xlsx', async (_event, filePath) => {
  requireTrustedFile(filePath);
  return analyzeWorkbook(filePath);
});

ipcMain.handle('run-desensitize', async (_event, { inputPath, selectedFields }) => {
  requireTrustedFile(inputPath);
  const destination = await dialog.showOpenDialog({
    title: '选择脱敏文件保存目录',
    properties: ['openDirectory', 'createDirectory']
  });
  if (destination.canceled || !destination.filePaths[0]) return { canceled: true };
  const outputDirectory = destination.filePaths[0];
  const names = outputNames(inputPath);
  const canWrite = await confirmOverwrite([
    path.join(outputDirectory, names.masked),
    path.join(outputDirectory, names.mapping)
  ]);
  if (!canWrite) return { canceled: true };
  const result = await desensitizeWorkbook(inputPath, selectedFields, outputDirectory);
  trustedFiles.add(path.resolve(result.maskedPath));
  trustedFiles.add(path.resolve(result.mappingPath));
  return { ...result, canceled: false };
});

ipcMain.handle('run-recover', async (_event, { maskedPath, mappingPath }) => {
  requireTrustedFile(maskedPath);
  requireTrustedFile(mappingPath);
  const destination = await dialog.showOpenDialog({
    title: '选择恢复文件保存目录',
    properties: ['openDirectory', 'createDirectory']
  });
  if (destination.canceled || !destination.filePaths[0]) return { canceled: true };
  const outputDirectory = destination.filePaths[0];
  const outputPath = path.join(outputDirectory, outputNames(maskedPath).recovered);
  if (!(await confirmOverwrite([outputPath]))) return { canceled: true };
  const result = await recoverWorkbook(maskedPath, mappingPath, outputDirectory);
  trustedFiles.add(path.resolve(result.outputPath));
  return { ...result, canceled: false };
});

ipcMain.handle('show-in-folder', async (_event, filePath) => {
  requireTrustedFile(filePath);
  shell.showItemInFolder(filePath);
});

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
