const http = require('http');
const fs = require('fs');

console.log("Starting parallel HTTP requests example");

function httpGet(url) {
  return new Promise((resolve, reject) => {
    console.log(`Making request to ${url}`);
    http.get(url, (error, response) => {
      if (error) {
        console.error(`Error fetching ${url}:`, error);
        reject(error);
        return;
      }

      console.log(`Received response from ${url} (${response.statusCode})`);
      resolve(response);
    });
  });
}

const urls = [
  'https://example.com',
  'https://httpbin.org/json',
  'https://httpbin.org/get',
  'https://postman-echo.com/get'
];

console.log(`Will fetch ${urls.length} URLs in parallel`);

const requests = urls.map(url => httpGet(url));

const startTime = Date.now();

Promise.all(requests)
  .then(responses => {
    const endTime = Date.now();
    const duration = (endTime - startTime) / 1000;

    console.log(`\nAll ${responses.length} requests completed in ${duration.toFixed(2)} seconds`);

    let summary = `# HTTP Request Results\n\n`;
    summary += `Completed at: ${new Date().toISOString()}\n`;
    summary += `Total time: ${duration.toFixed(2)} seconds\n\n`;

    responses.forEach((response, index) => {
      summary += `## Request ${index + 1}: ${urls[index]}\n`;
      summary += `Status: ${response.statusCode}\n`;
      summary += `Content Type: ${response.headers['content-type'] || 'unknown'}\n`;

      if (response.body) {
        const preview = response.body.substring(0, 100).replace(/\n/g, ' ');
        summary += `Body preview: ${preview}${response.body.length > 100 ? '...' : ''}\n`;
      }

      summary += '\n';
    });

    fs.writeFileSync('http-results.md', summary, 'utf8');
    console.log('Results written to http-results.md');
  })
  .catch(error => {
    console.error('Failed to complete all requests:', error);
  });

console.log("All requests initiated, now waiting for them to complete...");
console.log("The event loop will keep the program running until all requests finish");
