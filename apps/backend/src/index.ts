import { createApp } from "./app.js";
import { env } from "./lib/env.js";

createApp().listen(env.PORT, () => {
  console.log(`SetzO backend listening on port ${env.PORT}`);
});
