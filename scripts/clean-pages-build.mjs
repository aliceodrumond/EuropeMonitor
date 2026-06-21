import { rm } from "node:fs/promises";
import { join } from "node:path";

const generatedWorkerConfig = join("dist", "server", "wrangler.json");

await rm(generatedWorkerConfig, { force: true });
