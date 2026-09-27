const api = window.fileDesensitizer;
const state = {
  source: null,
  analysis: null,
  selected: new Set(),
  masked: null,
  mapping: null,
  busy: false
};

const byId = (id) => document.getElementById(id);
let toastTimer;

function showToast(message, error = false) {
  const toast = byId('toast');
  toast.textContent = message;
  toast.className = error ? 'show error' : 'show';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { toast.className = ''; }, 4200);
}

function errorMessage(error) {
  return error?.message?.replace(/^Error invoking remote method '[^']+': Error: /, '') || '操作失败';
}

function setBusy(busy, button, label) {
  state.busy = busy;
  if (button) {
    button.disabled = busy;
    button.textContent = busy ? '处理中…' : label;
  }
}

function currentSheet() {
  return state.analysis?.sheets.find((sheet) => sheet.name === byId('sheet-select').value);
}

function updateSelectionSummary() {
  byId('selection-summary').textContent = `已选择 ${state.selected.size} 个字段`;
  byId('run-desensitize').disabled = state.selected.size === 0 || state.busy;
}

function renderFields() {
  const body = byId('field-body');
  body.replaceChildren();
  const sheet = currentSheet();
  if (!sheet) return;
  for (const field of sheet.fields) {
    const row = document.createElement('tr');
    const checkCell = document.createElement('td');
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = state.selected.has(field.id);
    checkbox.addEventListener('change', () => {
      if (checkbox.checked) state.selected.add(field.id); else state.selected.delete(field.id);
      updateSelectionSummary();
    });
    checkCell.append(checkbox);

    const nameCell = document.createElement('td');
    nameCell.textContent = field.name;
    const typeCell = document.createElement('td');
    if (field.sensitiveTypeNames.length) {
      for (const name of field.sensitiveTypeNames) {
        const badge = document.createElement('span');
        badge.className = 'type-badge';
        badge.textContent = name;
        typeCell.append(badge);
      }
    } else {
      const label = document.createElement('span');
      label.className = 'not-sensitive';
      label.textContent = '未识别为敏感字段';
      typeCell.append(label);
    }
    const sampleCell = document.createElement('td');
    sampleCell.className = 'sample';
    sampleCell.textContent = field.sampleValues.join('、') || '—';
    row.append(checkCell, nameCell, typeCell, sampleCell);
    body.append(row);
  }
  updateSelectionSummary();
}

async function selectSource() {
  if (state.busy) return;
  try {
    const picked = await api.pickXlsx();
    if (!picked) return;
    state.source = picked;
    byId('source-name').textContent = picked.name;
    showToast('正在分析 Excel 字段…');
    state.analysis = await api.analyzeXlsx(picked.path);
    state.selected = new Set(state.analysis.sheets.flatMap((sheet) =>
      sheet.fields.filter((field) => field.isSensitive).map((field) => field.id)
    ));
    const select = byId('sheet-select');
    select.replaceChildren();
    state.analysis.sheets.forEach((sheet) => {
      const option = document.createElement('option');
      option.value = sheet.name;
      option.textContent = `${sheet.name}（${sheet.rowCount} 行）`;
      select.append(option);
    });
    byId('desensitize-upload').classList.add('hidden');
    byId('desensitize-result').classList.add('hidden');
    byId('analysis-panel').classList.remove('hidden');
    renderFields();
    showToast('字段分析完成');
  } catch (error) {
    showToast(errorMessage(error), true);
  }
}

function selectedFields() {
  return state.analysis.sheets.flatMap((sheet) => sheet.fields)
    .filter((field) => state.selected.has(field.id));
}

function showResult(container, title, lines, files) {
  container.replaceChildren();
  const heading = document.createElement('h2');
  heading.textContent = title;
  container.append(heading);
  lines.forEach((line) => {
    const paragraph = document.createElement('p');
    paragraph.textContent = line;
    container.append(paragraph);
  });
  const actions = document.createElement('div');
  actions.className = 'result-actions';
  files.forEach(({ label, path }) => {
    const button = document.createElement('button');
    button.className = 'secondary';
    button.textContent = label;
    button.addEventListener('click', () => api.showInFolder(path));
    actions.append(button);
  });
  container.append(actions);
  container.classList.remove('hidden');
}

async function runDesensitize() {
  const button = byId('run-desensitize');
  if (!state.source || !state.selected.size || state.busy) return;
  setBusy(true, button, '开始脱敏');
  try {
    const result = await api.desensitize(state.source.path, selectedFields());
    if (result.canceled) return;
    showResult(
      byId('desensitize-result'),
      '脱敏完成',
      [`共替换 ${result.replacementCount} 个单元格`, `脱敏文件：${result.maskedPath}`, `映射表：${result.mappingPath}`],
      [{ label: '查看脱敏文件', path: result.maskedPath }, { label: '查看映射表', path: result.mappingPath }]
    );
    showToast('脱敏文件和映射表已生成');
  } catch (error) {
    showToast(errorMessage(error), true);
  } finally {
    setBusy(false, button, '开始脱敏');
    updateSelectionSummary();
  }
}

async function pickRecoveryFile(kind) {
  if (state.busy) return;
  const picked = await api.pickXlsx();
  if (!picked) return;
  state[kind] = picked;
  byId(`${kind}-name`).textContent = picked.name;
  byId('run-recover').disabled = !(state.masked && state.mapping);
}

async function runRecover() {
  const button = byId('run-recover');
  if (!state.masked || !state.mapping || state.busy) return;
  setBusy(true, button, '开始恢复');
  try {
    const result = await api.recover(state.masked.path, state.mapping.path);
    if (result.canceled) return;
    showResult(
      byId('recover-result'),
      '恢复完成',
      [`共恢复 ${result.replacementCount} 个单元格`, `恢复文件：${result.outputPath}`],
      [{ label: '查看恢复文件', path: result.outputPath }]
    );
    showToast('恢复文件已生成');
  } catch (error) {
    showToast(errorMessage(error), true);
  } finally {
    setBusy(false, button, '开始恢复');
    button.disabled = !(state.masked && state.mapping);
  }
}

document.querySelectorAll('.nav-item').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.nav-item, .tab-panel').forEach((element) => element.classList.remove('active'));
    button.classList.add('active');
    byId(button.dataset.tab).classList.add('active');
  });
});
byId('pick-source').addEventListener('click', selectSource);
byId('change-source').addEventListener('click', selectSource);
byId('sheet-select').addEventListener('change', renderFields);
byId('select-sensitive').addEventListener('click', () => {
  state.selected = new Set(state.analysis.sheets.flatMap((sheet) =>
    sheet.fields.filter((field) => field.isSensitive).map((field) => field.id)
  ));
  renderFields();
});
byId('toggle-all').addEventListener('click', () => {
  const fields = currentSheet()?.fields || [];
  const allSelected = fields.every((field) => state.selected.has(field.id));
  fields.forEach((field) => allSelected ? state.selected.delete(field.id) : state.selected.add(field.id));
  renderFields();
});
byId('run-desensitize').addEventListener('click', runDesensitize);
byId('pick-masked').addEventListener('click', () => pickRecoveryFile('masked').catch((error) => showToast(errorMessage(error), true)));
byId('pick-mapping').addEventListener('click', () => pickRecoveryFile('mapping').catch((error) => showToast(errorMessage(error), true)));
byId('run-recover').addEventListener('click', runRecover);
