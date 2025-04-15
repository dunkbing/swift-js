console.log("Hello from SwiftJS!");
console.log("Multiple", "arguments", 123, true);
console.info("This is an informational message");
console.warn("This is a warning message");
console.error("This is an error message");
console.debug("This is a debug message");

const user = {
  name: "John Doe",
  age: 30,
  isActive: true,
  roles: ["admin", "user"]
};
console.log("User object:", user);

console.time("operation");

let sum = 0;
for (let i = 0; i < 1000000; i++) {
  sum += i;
}

console.timeEnd("operation");
console.log("Sum result:", sum);

console.assert(sum > 0, "Sum should be greater than 0");
console.assert(sum < 0, "This assertion will fail", "Sum is:", sum);

const nestedObject = {
  level1: {
    level2: {
      level3: {
        value: "deeply nested value",
        array: [1, 2, 3, { special: true }]
      }
    }
  }
};

console.log("Nested object:", nestedObject);

try {
  nonExistentFunction();
} catch (error) {
  console.error("Caught an error:", error);
}

console.log("Script execution completed");
