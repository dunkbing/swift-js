console.log("Running with arguments:", process.argv);
console.log("Current directory:", process.cwd);

const fs = require('fs');

fs.writeFileSync('output.txt', 'Hello from SwiftJS!', { encoding: 'utf8' });
console.log("File written successfully");

if (fs.existsSync('output.txt')) {
  const content = fs.readFileSync('output.txt', 'utf8');
  console.log("File content:", content);
}

const path = require('path');
const filePath = path.join(__dirname, 'some', 'nested', 'path', 'file.js');
console.log("Constructed path:", filePath);
console.log("Basename:", path.basename(filePath));
console.log("Directory name:", path.dirname(filePath));

console.log("About to set timeout...");
setTimeout(() => {
  console.log("Timeout executed after 1 second");

  console.log("Current file:", __filename);
  console.log("Current directory:", __dirname);

  const result = {
    success: true,
    message: "JavaScript execution completed"
  };

  console.log("Final result:", result);
}, 1000);

console.log("Script execution continues after setTimeout");
