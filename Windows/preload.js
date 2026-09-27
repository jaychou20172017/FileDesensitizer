const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('fileDesensitizer', {
  pickXlsx: () => ipcRenderer.invoke('pick-xlsx'),
  analyzeXlsx: (filePath) => ipcRenderer.invoke('analyze-xlsx', filePath),
  desensitize: (inputPath, selectedFields) => ipcRenderer.invoke(
    'run-desensitize', { inputPath, selectedFields }
  ),
  recover: (maskedPath, mappingPath) => ipcRenderer.invoke(
    'run-recover', { maskedPath, mappingPath }
  ),
  showInFolder: (filePath) => ipcRenderer.invoke('show-in-folder', filePath)
});
