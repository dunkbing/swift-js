try {
  nonExistentFunction();
} catch (error) {
  console.error("Caught explicitly:", error);
}

setTimeout(() => {
  undefinedVariable.someProperty = true;
}, 100);

console.log("Script continues execution after the try/catch block");

const nullObject = null;
nullObject.property = "This will fail";
