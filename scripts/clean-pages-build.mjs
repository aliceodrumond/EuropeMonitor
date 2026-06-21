import { writeFile } from "node:fs/promises";
import { join } from "node:path";

const generatedWorkerConfig = join("dist", "server", "wrangler.json");

await writeFile(
  generatedWorkerConfig,
  JSON.stringify(
    {
      pages_build_output_dir: "../client",
      compatibility_date: "2026-06-21",
    },
    null,
    2,
  ),
);
