import { mkdir, writeFile } from "node:fs/promises";

await mkdir("dist/server", { recursive: true });
await writeFile(
  "dist/server/index.js",
  `export default {
  fetch(request, _env, context) {
    return _env.ASSETS.fetch(request);
  },
};
`,
);
