const fs = require("fs");

// Check if directory exists, if not create it
if (!fs.existsSync('test-dir')) {
  console.log('Creating test directory...');
  fs.mkdirSync('test-dir');
} else {
  console.log('Test directory already exists');
}

// Create a nested directory structure
console.log('Creating nested directories...');
fs.mkdir('test-dir/nested/deep', { recursive: true }, (err) => {
  if (err) console.error('Error creating nested directories:', err);
  else console.log('Nested directories created successfully');
});

// Write to a file synchronously
console.log('Writing to file synchronously...');
fs.writeFileSync('test-dir/sync-file.txt', 'This was written synchronously');

// Read the file we just created
console.log('Reading file synchronously...');
const syncContent = fs.readFileSync('test-dir/sync-file.txt', 'utf8');
console.log('Sync file content:', syncContent);

// Write to a file asynchronously
console.log('Writing to file asynchronously...');
fs.writeFile('test-dir/async-file.txt', 'This was written asynchronously', (err) => {
  if (err) {
    console.error('Error writing async file:', err);
    return;
  }

  console.log('File written successfully');

  // Read the file asynchronously after it's been written
  fs.readFile('test-dir/async-file.txt', 'utf8', (readErr, data) => {
    if (readErr) {
      console.error('Error reading async file:', readErr);
      return;
    }
    console.log('Async file content:', data);
  });
});

// Check if a file exists (both ways)
fs.exists('test-dir/sync-file.txt', (exists) => {
  console.log('Does sync-file.txt exist? (async check):', exists);
});

console.log('Does sync-file.txt exist? (sync check):', fs.existsSync('test-dir/sync-file.txt'));

// read directory contents
setTimeout(() => {
  console.log('Reading directory contents synchronously...');
  const files = fs.readdirSync('test-dir');
  console.log('Directory contents:', files);

  console.log('Reading directory contents asynchronously...');
  fs.readdir('test-dir', (err, asyncFiles) => {
    if (err) {
      console.error('Error reading directory:', err);
      return;
    }
    console.log('Directory contents (async):', asyncFiles);
  });
}, 1000);

// File stats
setTimeout(() => {
  console.log('Getting file stats synchronously...');
  const stats = fs.statSync('test-dir/sync-file.txt');
  console.log('File size:', stats.size);
  console.log('Is file?', stats.isFile());
  console.log('Is directory?', stats.isDirectory());
  // console.log('Modified time:', new Date(stats.mtime)); // error when logging date.

  console.log('Getting file stats asynchronously...');
  fs.stat('test-dir/async-file.txt', (err, asyncStats) => {
    if (err) {
      console.error('Error getting file stats:', err);
      return;
    }
    console.log('Async file size:', asyncStats.size);
    console.log('Is file? (async)', asyncStats.isFile());
    console.log('Is directory? (async)', asyncStats.isDirectory());
    // console.log('Modified time (async):', new Date(asyncStats.mtime));
  });
}, 2000);

// wait for all async operations to complete
console.log('Script execution continues...');
