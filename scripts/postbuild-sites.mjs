import { rename, writeFile } from "node:fs/promises";

await rename("dist/server/index.js", "dist/server/app.js");
await writeFile(
  "dist/server/index.js",
  `import handler from "./app.js";

export default {
  fetch(request, _env, context) {
    return handler(request, context);
  },
};
`,
);
