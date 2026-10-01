#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const generatedPath = path.join(root, 'ios', 'Flutter', 'Generated.xcconfig');
const outputPath = path.join(root, 'ios', 'Flutter', 'LocalDartDefines.xcconfig');
const configPath = path.join(root, 'config', 'dev.json');

const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const requiredValues = {
  SUPABASE_URL: stringValue(config.SUPABASE_URL),
  SUPABASE_PUBLISHABLE_KEY: stringValue(config.SUPABASE_PUBLISHABLE_KEY),
};

for (const [key, value] of Object.entries(requiredValues)) {
  if (!value) {
    throw new Error(`${key} 값이 config/dev.json에 없습니다.`);
  }
}

const existingDefines = readExistingDefines();
const mergedDefines = existingDefines.filter(
  (define) =>
    !define.startsWith('SUPABASE_URL=') &&
    !define.startsWith('SUPABASE_PUBLISHABLE_KEY='),
);

for (const [key, value] of Object.entries(requiredValues)) {
  mergedDefines.push(`${key}=${value}`);
}

const encoded = mergedDefines.map((define) =>
  Buffer.from(define, 'utf8').toString('base64'),
);

fs.writeFileSync(
  outputPath,
  [
    '// Xcode 직접 실행용 로컬 Dart define입니다.',
    '// config/dev.json에서 생성되며 Git에는 포함하지 않습니다.',
    `DART_DEFINES=${encoded.join(',')}`,
    '',
  ].join('\n'),
);

console.log('iOS 로컬 Dart define을 갱신했습니다.');

function readExistingDefines() {
  if (!fs.existsSync(generatedPath)) {
    return [];
  }
  const content = fs.readFileSync(generatedPath, 'utf8');
  const line = content.split('\n').find((entry) =>
    entry.startsWith('DART_DEFINES='),
  );
  if (!line) {
    return [];
  }
  return line
    .replace('DART_DEFINES=', '')
    .split(',')
    .filter(Boolean)
    .map((value) => Buffer.from(value, 'base64').toString('utf8'));
}

function stringValue(value) {
  return typeof value === 'string' ? value.trim() : '';
}
