const fs = require('node:fs');
const path = require('node:path');
const ExcelJS = require('exceljs');
const { TYPES, detectColumnTypes, maskedValue } = require('./sensitive');

const MAX_FILE_SIZE = 100 * 1024 * 1024;

function validateXlsx(filePath) {
  if (path.extname(filePath).toLowerCase() !== '.xlsx') throw new Error('当前版本仅支持 .xlsx Excel 文件');
  const stat = fs.statSync(filePath);
  if (stat.size > MAX_FILE_SIZE) throw new Error('文件超过 100MB 处理上限');
}

function cellToText(cell) {
  const value = cell?.value;
  if (value == null) return '';
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') {
    if (Object.hasOwn(value, 'result')) return value.result == null ? '' : String(value.result);
    if (Array.isArray(value.richText)) return value.richText.map((part) => part.text || '').join('');
    if (value.text != null) return String(value.text);
    if (value.error != null) return String(value.error);
  }
  return String(value);
}

async function loadWorkbook(filePath) {
  validateXlsx(filePath);
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(filePath);
  return workbook;
}

function analyzeLoadedWorkbook(workbook, filePath = '') {
  const sheets = workbook.worksheets.map((worksheet, sheetIndex) => {
    const columnCount = Math.max(worksheet.columnCount, worksheet.getRow(1).cellCount);
    const headers = Array.from({ length: columnCount }, (_, index) => cellToText(worksheet.getRow(1).getCell(index + 1)));
    const fields = headers.map((header, index) => {
      const samples = [];
      for (let row = 2; row <= worksheet.rowCount && samples.length < 20; row += 1) {
        const value = cellToText(worksheet.getRow(row).getCell(index + 1)).trim();
        if (value) samples.push(value);
      }
      const name = header.trim() || `列${index + 1}`;
      const sensitiveTypes = detectColumnTypes(name, samples);
      return {
        id: `${sheetIndex}:${index + 1}`,
        sheetName: worksheet.name,
        columnIndex: index + 1,
        name,
        sensitiveTypes,
        sensitiveTypeNames: sensitiveTypes.map((type) => TYPES[type]),
        isSensitive: sensitiveTypes.length > 0,
        sampleValues: samples.slice(0, 5)
      };
    });
    return { name: worksheet.name, rowCount: Math.max(0, worksheet.rowCount - 1), headers, fields };
  });
  return { fileName: path.basename(filePath), sheets };
}

async function analyzeWorkbook(filePath) {
  const workbook = await loadWorkbook(filePath);
  return analyzeLoadedWorkbook(workbook, filePath);
}

function outputNames(inputPath) {
  const base = path.basename(inputPath, path.extname(inputPath));
  return {
    masked: `${base}_脱敏.xlsx`,
    mapping: `${base}_脱敏映射表.xlsx`,
    recovered: `${base.endsWith('_脱敏') ? base.slice(0, -3) : base}_脱敏恢复版.xlsx`
  };
}

function ensureDirectory(directory) {
  fs.mkdirSync(directory, { recursive: true });
}

async function writeMappingWorkbook(mappings, outputPath) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('脱敏映射表', { views: [{ state: 'frozen', ySplit: 1 }] });
  sheet.columns = [
    { header: '字段名', key: 'fieldName', width: 24 },
    { header: '原始值', key: 'originalValue', width: 36 },
    { header: '脱敏值', key: 'maskedValue', width: 36 }
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE8F0FE' } };
  mappings.forEach((mapping) => sheet.addRow(mapping));
  sheet.autoFilter = { from: 'A1', to: `C${Math.max(1, mappings.length + 1)}` };
  await workbook.xlsx.writeFile(outputPath);
}

async function desensitizeWorkbook(inputPath, selectedFields, outputDirectory) {
  if (!Array.isArray(selectedFields) || selectedFields.length === 0) throw new Error('请至少选择一个脱敏字段');
  const workbook = await loadWorkbook(inputPath);
  const allRealValues = new Set();
  for (const field of selectedFields) {
    const sheet = workbook.getWorksheet(field.sheetName);
    if (!sheet) continue;
    for (let row = 2; row <= sheet.rowCount; row += 1) {
      const value = cellToText(sheet.getRow(row).getCell(field.columnIndex)).trim();
      if (value) allRealValues.add(value);
    }
  }

  const maskByOriginal = new Map();
  const originalByMask = new Map();
  const seenMappings = new Set();
  const mappings = [];
  let replacementCount = 0;

  for (const field of selectedFields) {
    const sheet = workbook.getWorksheet(field.sheetName);
    if (!sheet) continue;
    for (let row = 2; row <= sheet.rowCount; row += 1) {
      const cell = sheet.getRow(row).getCell(field.columnIndex);
      const original = cellToText(cell).trim();
      if (!original) continue;
      let masked = maskByOriginal.get(original);
      if (!masked) {
        let retry = 0;
        do {
          masked = maskedValue(original, field.sensitiveTypes?.[0], retry);
          retry += 1;
        } while ((masked === original || allRealValues.has(masked)
          || (originalByMask.has(masked) && originalByMask.get(masked) !== original)) && retry <= 100);
        maskByOriginal.set(original, masked);
        originalByMask.set(masked, original);
      }
      cell.value = masked;
      replacementCount += 1;
      const key = `${field.name}\u0000${original}`;
      if (!seenMappings.has(key)) {
        seenMappings.add(key);
        mappings.push({ fieldName: field.name, originalValue: original, maskedValue: masked });
      }
    }
  }

  if (!replacementCount) throw new Error('所选字段没有匹配到可脱敏的单元格');
  mappings.sort((a, b) => `${a.fieldName}\u0000${a.originalValue}`.localeCompare(`${b.fieldName}\u0000${b.originalValue}`, 'zh-CN'));
  ensureDirectory(outputDirectory);
  const names = outputNames(inputPath);
  const maskedPath = path.join(outputDirectory, names.masked);
  const mappingPath = path.join(outputDirectory, names.mapping);
  await workbook.xlsx.writeFile(maskedPath);
  await writeMappingWorkbook(mappings, mappingPath);
  return { maskedPath, mappingPath, mappings, replacementCount };
}

async function readMappings(mappingPath) {
  const workbook = await loadWorkbook(mappingPath);
  const sheet = workbook.worksheets[0];
  if (!sheet) throw new Error('映射表中没有工作表');
  const mappings = [];
  for (let row = 2; row <= sheet.rowCount; row += 1) {
    const fieldName = cellToText(sheet.getRow(row).getCell(1)).trim();
    const originalValue = cellToText(sheet.getRow(row).getCell(2));
    const maskedValue = cellToText(sheet.getRow(row).getCell(3));
    if (fieldName && maskedValue) mappings.push({ fieldName, originalValue, maskedValue });
  }
  if (!mappings.length) throw new Error('映射表中没有可用的脱敏记录');
  return mappings;
}

async function recoverWorkbook(maskedPath, mappingPath, outputDirectory) {
  const workbook = await loadWorkbook(maskedPath);
  const mappings = await readMappings(mappingPath);
  const reverseByField = new Map();
  for (const mapping of mappings) {
    if (!reverseByField.has(mapping.fieldName)) reverseByField.set(mapping.fieldName, new Map());
    reverseByField.get(mapping.fieldName).set(mapping.maskedValue, mapping.originalValue);
  }
  let replacementCount = 0;
  for (const sheet of workbook.worksheets) {
    for (let column = 1; column <= sheet.columnCount; column += 1) {
      const header = cellToText(sheet.getRow(1).getCell(column)).trim() || `列${column}`;
      const reverse = reverseByField.get(header);
      if (!reverse) continue;
      for (let row = 2; row <= sheet.rowCount; row += 1) {
        const cell = sheet.getRow(row).getCell(column);
        const current = cellToText(cell);
        if (reverse.has(current)) {
          cell.value = reverse.get(current);
          replacementCount += 1;
        }
      }
    }
  }
  if (!replacementCount) throw new Error('映射表与脱敏文件不匹配，未找到可恢复的单元格');
  ensureDirectory(outputDirectory);
  const outputPath = path.join(outputDirectory, outputNames(maskedPath).recovered);
  await workbook.xlsx.writeFile(outputPath);
  return { outputPath, mappings, replacementCount };
}

module.exports = {
  MAX_FILE_SIZE,
  analyzeLoadedWorkbook,
  analyzeWorkbook,
  desensitizeWorkbook,
  recoverWorkbook,
  readMappings,
  cellToText,
  outputNames
};
