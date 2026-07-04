import { LuaFactory } from "wasmoon";
import * as fs from "fs";
import * as path from "path";

async function main() {
  console.log("Initializing Lua VM (Wasmoon)...");
  const factory = new LuaFactory();
  const lua = await factory.createEngine();

  // Redirect Lua print to TS console
  lua.global.set("print", (...args: any[]) => {
    console.log("[LUA]", ...args.map(arg => typeof arg === "object" ? JSON.stringify(arg) : String(arg)));
  });

  // Expose a helper to read files relative to workspace root
  lua.global.set("readProjectFile", (relativePath: string) => {
    const fullPath = path.resolve(process.cwd(), "..", relativePath);
    if (!fs.existsSync(fullPath)) {
      throw new Error(`File not found: ${fullPath}`);
    }
    return fs.readFileSync(fullPath, "utf-8");
  });

  // Expose a failure hook for tests
  let failed = false;
  lua.global.set("testFailed", (message: string) => {
    console.error(`\x1b[31m[TEST FAILED] ${message}\x1b[0m`);
    failed = true;
  });

  console.log("Running SpectrumDB Test Suite...");
  try {
    // Run the main test specification file
    const specPath = path.resolve(process.cwd(), "spectrumdb_spec.lua");
    const specContent = fs.readFileSync(specPath, "utf-8");
    await lua.doString(specContent);
  } catch (err: any) {
    console.error("\x1b[31m[LUA ERROR]\x1b[0m", err.message || err);
    failed = true;
  }

  if (failed) {
    console.log("\x1b[31mSome tests failed.\x1b[0m");
    process.exit(1);
  } else {
    console.log("\x1b[32mAll tests passed successfully!\x1b[0m");
    process.exit(0);
  }
}

main().catch(err => {
  console.error("Test runner failed:", err);
  process.exit(1);
});
