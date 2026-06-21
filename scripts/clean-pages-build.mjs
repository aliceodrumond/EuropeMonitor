import { rm } from "node:fs/promises";
import { join } from "node:path";

const generatedWorkerConfig = join("dist", "server", "wrangler.json");
const generatedDeployConfig = join(".wrangler", "deploy", "config.json");

await rm(generatedWorkerConfig, { force: true });
await rm(generatedDeployConfig, { force: true });
