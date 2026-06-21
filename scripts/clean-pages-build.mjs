import { rm } from "node:fs/promises";
import { join } from "node:path";

const generatedWorkerConfig = join("dist", "server", "wrangler.json");
const generatedWranglerState = ".wrangler";

await rm(generatedWorkerConfig, { force: true });
await rm(generatedWranglerState, { recursive: true, force: true });
