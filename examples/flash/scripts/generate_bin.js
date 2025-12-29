const fs = require('fs');

const fileBytes = [];
for (let i = 0; i < 256; i += 1) {
    fileBytes.push(i);
}

fs.writeFileSync('./binaries/numbers.bin', Buffer.from(fileBytes));