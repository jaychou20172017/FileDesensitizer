#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";
import JSZip from "jszip";

const outputDir = process.argv[2];
if (!outputDir) {
  throw new Error("usage: generate_excel_fixture.mjs <output-dir>");
}

await fs.mkdir(outputDir, { recursive: true });

const workbook = Workbook.create();
const notes = workbook.worksheets.add("说明");
const data = workbook.worksheets.add("人员调整");

notes.getRange("A1:B3").values = [
  ["回归场景", "验证内容"],
  ["稀疏列", "G/H/J 之间含空列和空单元格"],
  ["公式列", "J 列通过公式引用姓名"],
];

data.getRange("A1:J4").values = [
  ["编号", null, null, null, null, null, "原姓名", "新姓名", null, "审批人"],
  [1, null, null, null, null, null, "张三", "李四", null, null],
  [2, null, null, null, null, null, "王芳", null, null, null],
  [3, null, null, null, null, null, "赵敏", "张三", null, null],
];
data.getRange("J2:J4").formulas = [["=G2"], ["=G3"], ["=H4"]];

for (const sheet of [notes, data]) {
  sheet.showGridLines = false;
  sheet.freezePanes.freezeRows(1);
  const used = sheet.getUsedRange();
  used.format.font = { name: "Arial", size: 11, color: "#1F2937" };
  used.format.autofitColumns();
  sheet.getRange(`A1:${sheet === notes ? "B" : "J"}1`).format = {
    fill: "#1F4E78",
    font: { name: "Arial", size: 11, bold: true, color: "#FFFFFF" },
    horizontalAlignment: "center",
    verticalAlignment: "center",
  };
}
notes.getRange("A1:B3").format.borders = { preset: "all", style: "thin", color: "#D9E2F3" };
data.getRange("A1:J4").format.borders = { preset: "outside", style: "thin", color: "#D9E2F3" };
data.getRange("A1:A4").format.columnWidth = 10;
data.getRange("G1:J4").format.columnWidth = 14;

const structure = await workbook.inspect({
  kind: "table,formula",
  sheetId: "人员调整",
  range: "A1:J4",
  include: "values,formulas",
  tableMaxRows: 6,
  tableMaxCols: 12,
  maxChars: 5000,
});
console.log(structure.ndjson);

const formulaErrors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!",
  options: { useRegex: true, maxResults: 100 },
  summary: "Excel regression fixture formula error scan",
});
if (formulaErrors.ndjson.includes('"matchCount":') && !formulaErrors.ndjson.includes('"matchCount":0')) {
  throw new Error(`formula error detected: ${formulaErrors.ndjson}`);
}

for (const sheetName of ["说明", "人员调整"]) {
  const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(
    path.join(outputDir, `${sheetName}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const outputPath = path.join(outputDir, "excel_regression.xlsx");
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);

// Cross the worksheet relationship targets while also swapping the XML parts.
// The workbook still displays 说明 then 人员调整, but display order no longer
// matches sheet1.xml/sheet2.xml order, reproducing the former path-order bug.
const zip = await JSZip.loadAsync(await fs.readFile(outputPath));
const sheet1 = await zip.file("xl/worksheets/sheet1.xml").async("uint8array");
const sheet2 = await zip.file("xl/worksheets/sheet2.xml").async("uint8array");
zip.file("xl/worksheets/sheet1.xml", sheet2);
zip.file("xl/worksheets/sheet2.xml", sheet1);

const relsPath = "xl/_rels/workbook.xml.rels";
const rels = await zip.file(relsPath).async("string");
const crossed = rels
  .replace(/(Target="[^"]*worksheets\/)sheet1\.xml"/, "$1__swap__.xml\"")
  .replace(/(Target="[^"]*worksheets\/)sheet2\.xml"/, "$1sheet1.xml\"")
  .replace(/(Target="[^"]*worksheets\/)__swap__\.xml"/, "$1sheet2.xml\"");
if (crossed === rels || crossed.includes("__swap__")) {
  throw new Error("unable to cross worksheet relationship targets");
}
zip.file(relsPath, crossed);
await fs.writeFile(outputPath, await zip.generateAsync({ type: "nodebuffer" }));

