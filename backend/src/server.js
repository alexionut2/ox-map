import { createApp } from './app.js';
import { ReportStore } from './store.js';
import { TomTomIncidents } from './tomtom.js';

const port = Number(process.env.PORT || 8080);
const store = new ReportStore({ file: process.env.OXYDE_DATA_FILE || 'data/reports.json' });
await store.load();

const providers = [];
if (process.env.TOMTOM_API_KEY) providers.push(new TomTomIncidents({ apiKey: process.env.TOMTOM_API_KEY }));
else console.warn('TOMTOM_API_KEY is not set: /v1/incidents returns driver reports only.');

const server = createApp({ store, providers, adminToken: process.env.OXYDE_ADMIN_TOKEN || null });
server.listen(port, () => console.log(`Oxyde backend listening on :${port}`));

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    server.close();
    await store.flush();
    process.exit(0);
  });
}
