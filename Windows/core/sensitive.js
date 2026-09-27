const crypto = require('node:crypto');

const TYPES = Object.freeze({
  phone: '手机号',
  idCard: '身份证号',
  email: '邮箱',
  bankCard: '银行卡号',
  chineseName: '姓名',
  companyName: '供应商名称',
  landline: '固定电话'
});

const surnames = new Set(
  '王李张刘陈杨黄赵周吴徐孙马胡朱郭何罗高林郑梁谢唐许韩冯邓曹彭曾萧田董潘袁于蒋蔡余杜叶程苏魏吕丁任沈姚卢姜崔钟谭陆汪范金石廖贾夏韦付方白邹孟熊秦邱江尹薛闫段雷侯龙史陶黎贺顾毛郝龚邵万钱严覃武戴莫孔向汤温康常阮倪童柳鲍屈庞蓝聂齐鲁辛庄殷章詹祁管祝左涂谷时舒耿牟卜路关岳樊凌纪柯焦池甘查牛敖单包司申冉游兰宁芦季成盛乔裴房代迟'.split('')
);

const personHeaders = ['姓名', '参与人员', '同行人', '联系人', '负责人', '审批人', '经办人', '审核人'];
const companyHeaders = ['供应商名称', '公司名称', '单位名称', '厂商名称', '客户名称'];

function isChineseName(value) {
  const parts = String(value ?? '').trim().split(/[\/\n]/).map((part) => part.trim()).filter(Boolean);
  return parts.length > 0 && parts.every((part) =>
    part.length >= 2 && part.length <= 3 && /^[\u4E00-\u9FFF]+$/u.test(part) && surnames.has(part[0])
  );
}

function detectValueTypes(value) {
  const text = String(value ?? '').trim();
  if (!text) return [];
  const found = [];
  const idCard = /(?:^|\D)(?:\d{17}[\dXx]|\d{15})(?:$|\D)/u.test(text);
  if (idCard) found.push('idCard');
  if (!idCard && /(?:^|\D)1[3-9]\d{9}(?:$|\D)/u.test(text)) found.push('phone');
  if (/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/u.test(text)) found.push('email');
  if (!idCard && /(?:^|\D)\d{16,19}(?:$|\D)/u.test(text)) found.push('bankCard');
  if (isChineseName(text)) found.push('chineseName');
  if (/(?<![\p{Script=Han}A-Za-z0-9])[\p{Script=Han}A-Za-z0-9（）()·&]{2,40}?(?:股份有限公司|有限责任公司|有限公司)(?![\p{Script=Han}A-Za-z0-9])/u.test(text)) {
    found.push('companyName');
  }
  if (/(?:^|\D)0\d{2,3}-?\d{7,8}(?:$|\D)/u.test(text)) found.push('landline');
  return found;
}

function detectColumnTypes(header, values) {
  const samples = values.map((value) => String(value).trim()).filter(Boolean);
  if (!samples.length) return [];
  const hits = new Map();
  for (const sample of samples) {
    for (const type of detectValueTypes(sample)) hits.set(type, (hits.get(type) || 0) + 1);
  }
  const result = [];
  for (const [type, count] of hits) {
    const threshold = type === 'chineseName'
      ? Math.max(2, Math.floor(samples.length / 2))
      : Math.max(1, Math.floor(samples.length / 3));
    if (count >= threshold) result.push(type);
  }
  const normalized = String(header).replace(/\s+/gu, '');
  if (companyHeaders.some((hint) => normalized.includes(hint)) && !result.includes('companyName')) {
    result.push('companyName');
  }
  if (personHeaders.some((hint) => normalized.includes(hint))
      && samples.some(isChineseName) && !result.includes('chineseName')) {
    result.push('chineseName');
  }
  return result;
}

function hashBytes(seed) {
  return crypto.createHash('sha256').update(`${seed}FD_v1_salt`, 'utf8').digest();
}

function maskedValue(original, preferredType, retry = 0) {
  const bytes = hashBytes(retry ? `${original}_r${retry}` : original);
  switch (preferredType || detectValueTypes(original)[0]) {
    case 'phone': {
      const prefixes = ['39', '58', '68', '78', '88', '98', '38', '59'];
      return `1${prefixes[bytes[0] % prefixes.length]}${String(bytes.readUInt32BE(0) % 100000000).padStart(8, '0')}`;
    }
    case 'idCard': {
      const areas = ['110101', '310101', '440103', '320102', '330102'];
      const birth = `${1960 + (bytes[1] % 50)}${String(1 + (bytes[2] % 12)).padStart(2, '0')}${String(1 + (bytes[3] % 28)).padStart(2, '0')}`;
      return `${areas[bytes[0] % areas.length]}${birth}${String(bytes.readUInt32BE(4) % 10000).padStart(4, '0')}`;
    }
    case 'email': {
      const names = ['user', 'info', 'admin', 'service', 'mail'];
      const domains = ['example.com', 'domain.cn', 'test.org', 'mail.cn'];
      return `${names[bytes[0] % names.length]}${String(bytes.readUInt16BE(2) % 10000).padStart(4, '0')}@${domains[bytes[1] % domains.length]}`;
    }
    case 'bankCard':
      return Array.from({ length: String(original).length }, (_, index) => bytes[index % bytes.length] % 10).join('');
    case 'chineseName': {
      const family = '张王李赵陈杨黄周吴徐孙马胡朱郭何罗高林郑梁谢唐许邓韩冯曹彭曾肖田董潘袁蔡蒋余于杜叶程苏魏吕丁任卢姚沈钟姜崔谭陆范汪廖石金韦贾夏付方白邹孟熊秦邱江尹薛闫段雷侯龙黎史陶贺毛郝顾龚邵万钱严覃武戴莫孔向汤温康';
      const given = '明华伟芳敏静丽强磊洋勇艳涛军杰文波斌霞平刚桂英辉玲秀峰燕红志健宁欣玉兰海亮飞超雪晶梅娟威鹏蕾睿颖林佳鑫博帅阳悦成云庆新龙洪春义喜美瑞金东长江凤丹莉亚秋良';
      return `${family[bytes[0] % family.length]}${given[bytes[4] % given.length]}${given[bytes[8] % given.length]}`;
    }
    case 'companyName': {
      const suffix = ['股份有限公司', '有限责任公司', '有限公司'].find((item) => String(original).endsWith(item)) || '有限公司';
      return `供应商_${bytes.subarray(0, 4).toString('hex').toUpperCase()}${suffix}`;
    }
    case 'landline': {
      const codes = ['010', '021', '020', '0755', '0571', '028', '025', '027'];
      return `${codes[bytes[0] % codes.length]}-${String(bytes.readUInt32BE(1) % 100000000).padStart(8, '0')}`;
    }
    default:
      return `MASKED_${bytes.subarray(0, 4).toString('hex').toUpperCase()}`;
  }
}

module.exports = { TYPES, detectValueTypes, detectColumnTypes, isChineseName, maskedValue };
