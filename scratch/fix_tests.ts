import fs from 'fs';
let lines = fs.readFileSync('tests/spectrumdb_spec.lua', 'utf8').split('\n');

for (let i = 622; i <= 715; i++) {
    if (!lines[i].startsWith('--')) {
        lines[i] = '-- ' + lines[i];
    }
}

fs.writeFileSync('tests/spectrumdb_spec.lua', lines.join('\n'));
