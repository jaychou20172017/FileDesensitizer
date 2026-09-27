const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const ExcelJS = require('exceljs');
const { detectValueTypes, isChineseName } = require('../core/sensitive');
const {
  analyzeWorkbook,
  desensitizeWorkbook,
  recoverWorkbook,
  outputNames
} = require('../core/workbook');

async function createFixture(filePath) {
  const workbook = new ExcelJS.Workbook();
  const notes = workbook.addWorksheet('说明');
  notes.addRow(['回归场景', '验证内容']);
  notes.addRow(['Windows', 'Excel 脱敏与恢复']);
  const sheet = workbook.addWorksheet('人员调整');
  sheet.addRow(['编号', '', '', '', '', '', '原姓名', '新姓名', '', '审批人']);
  sheet.addRow([1, '', '', '', '', '', '张三', '李四', '', { formula: 'G2', result: '张三' }]);
  sheet.addRow([2, '', '', '', '', '', '王芳', '', '', { formula: 'G3', result: '王芳' }]);
  sheet.addRow([3, '', '', '', '', '', '赵敏', '张三', '', { formula: 'H4', result: '张三' }]);
  await workbook.xlsx.writeFile(filePath);
}

async function valuesAt(filePath, sheetName, columns) {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.readFile(filePath);
  const sheet = workbook.getWorksheet(sheetName);
  return columns.flatMap((column) => {
    const values = [];
    for (let row = 2; row <= sheet.rowCount; row += 1) {
      const value = sheet.getRow(row).getCell(column).value;
      values.push(typeof value === 'object' && value?.result != null ? String(value.result) : String(value ?? ''));
    }
    return values;
  });
}

test('敏感数据规则与格式边界', () => {
  assert.deepEqual(detectValueTypes('13812345678'), ['phone']);
  assert.deepEqual(detectValueTypes('110101199003071234'), ['idCard']);
  assert.ok(detectValueTypes('杭州博日科技股份有限公司').includes('companyName'));
  assert.equal(detectValueTypes('广东省深圳市宝安区福海街道远东东路2号').length, 0);
  assert.equal(isChineseName('张三/李四'), true);
  assert.equal(isChineseName('数据中台'), false);
  assert.equal(outputNames('/tmp/客户清单_脱敏.xlsx').recovered, '客户清单_脱敏恢复版.xlsx');
});

test('Excel 分析、同名一致脱敏与恢复端到端', async (t) => {
  const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'file-desensitizer-win-test-'));
  t.after(() => fs.rmSync(tempDirectory, { recursive: true, force: true }));
  const fixturePath = path.join(tempDirectory, '人员调整.xlsx');
  await createFixture(fixturePath);

  const analysis = await analyzeWorkbook(fixturePath);
  assert.deepEqual(analysis.sheets.map((sheet) => sheet.name), ['说明', '人员调整']);
  const personnel = analysis.sheets.find((sheet) => sheet.name === '人员调整');
  const selected = personnel.fields.filter((field) => ['原姓名', '新姓名', '审批人'].includes(field.name));
  assert.equal(selected.length, 3);
  assert.ok(selected.every((field) => field.sensitiveTypes.includes('chineseName')));

  const originalValues = await valuesAt(fixturePath, '人员调整', [7, 8, 10]);
  const masked = await desensitizeWorkbook(fixturePath, selected, tempDirectory);
  assert.equal(masked.replacementCount, 8);
  assert.ok(fs.existsSync(masked.maskedPath));
  assert.ok(fs.existsSync(masked.mappingPath));
  const zhangMappings = masked.mappings.filter((mapping) => mapping.originalValue === '张三');
  assert.ok(zhangMappings.length >= 2);
  assert.equal(new Set(zhangMappings.map((mapping) => mapping.maskedValue)).size, 1);

  const maskedValues = await valuesAt(masked.maskedPath, '人员调整', [7, 8, 10]);
  assert.notDeepEqual(maskedValues, originalValues);
  const recovered = await recoverWorkbook(masked.maskedPath, masked.mappingPath, tempDirectory);
  assert.equal(recovered.replacementCount, 8);
  assert.deepEqual(await valuesAt(recovered.outputPath, '人员调整', [7, 8, 10]), originalValues);
});

test('拒绝非 XLSX 文件', async () => {
  await assert.rejects(() => analyzeWorkbook('/tmp/示例.docx'), /仅支持 \.xlsx/);
});
