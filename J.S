// Binny Slack Bot – for Contents Jobs (Initial + Progress Form Cycle)
const { App, ExpressReceiver } = require('@slack/bolt');
const express = require('express');
const fetch = (...args) => import('node-fetch').then(({ default: fetch }) => fetch(...args));

const expressReceiver = new ExpressReceiver({
  signingSecret: process.env.SLACK_SIGNING_SECRET,
  endpoints: '/slack/events',
  processBeforeResponse: true,
  bodyParser: false
});

const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  signingSecret: process.env.SLACK_SIGNING_SECRET,
  receiver: expressReceiver,
});

const PIPEDRIVE_API_TOKEN = process.env.PIPEDRIVE_API_TOKEN;
const INITIAL_FORM_URL = 'https://docs.google.com/forms/d/e/1FAIpQLScOHXE_h7gr_kagnUy-xTtV_gJsyTAMl7NtjlV4OBA1yPsZzw/viewform?usp=pp_url&entry.1514728493=';
const PROGRESS_FORM_URL = 'https://docs.google.com/forms/d/e/1FAIpQLSck9PRgRSGHWWgqIy0UJDC6r51Ihv5TIFKBILs-_sEzrkY7PA/viewform?usp=pp_url&entry.1942941566=';

const recentlyStarted = new Set();

function extractJobNumber(channelName) {
  const match = channelName.match(/deal(\d+)/);
  return match ? `job-${match[1]}` : null;
}

async function runStartWorkflow(channelId, client) {
  try {
    const info = await client.conversations.info({ channel: channelId });
    const channelName = info.channel?.name || 'UNKNOWN';
    const jobNumber = extractJobNumber(channelName);

    if (!jobNumber) return;

    const formLink = `${INITIAL_FORM_URL}${encodeURIComponent(jobNumber)}`;

    await client.chat.postMessage({
      channel: channelId,
      text: `📦 Please fill out the *Contents Initial Form* for *${jobNumber}*:
<${formLink}|Contents Initial Form>`
    });
  } catch (err) {
    console.error('❌ Binny start error:', err);
  }
}

app.event('member_joined_channel', async ({ event, client }) => {
  try {
    if (event.user === 'USLACKBOT') return;

    const channelId = event.channel;
    if (recentlyStarted.has(channelId)) return;

    const info = await client.conversations.info({ channel: channelId });
    const name = info.channel?.name || '';

    if (name.includes('deal')) {
      recentlyStarted.add(channelId);
      setTimeout(() => recentlyStarted.delete(channelId), 10000);

      await new Promise(r => setTimeout(r, 5000));
      await runStartWorkflow(channelId, client);
    }
  } catch (err) {
    console.error('❌ Error in Binny channel join handler:', err);
  }
});

app.command('/start', async ({ command, ack, client }) => {
  await ack();
  await runStartWorkflow(command.channel_id, client);
});

const expressApp = expressReceiver.app;
expressApp.use(express.json());

expressApp.get('/slack/events', (req, res) => {
  res.status(200).send('Binny event route ready');
});

expressApp.post('/slack/events', (req, res) => {
  if (req.body?.type === 'url_verification') {
    return res.status(200).send(req.body.challenge);
  } else {
    res.status(200).end();
  }
});

expressApp.post('/trigger-contents-progress-form', async (req, res) => {
  const jobNumber = req.body?.jobNumber;
  const progressCount = req.body?.progressCount || 1;
  const formDate = typeof req.body?.formDate === 'string' ? req.body.formDate : 'DATE_MISSING';

  if (!jobNumber || !jobNumber.toLowerCase().includes('deal')) {
    console.warn(`⚠️ Invalid job number for progress form: ${jobNumber}`);
    return res.status(400).send('Invalid job number');
  }

  const channel = jobNumber.toLowerCase();
  const title = `Contents Progress ${progressCount} – ${formDate}`;
  const link = `${PROGRESS_FORM_URL}${encodeURIComponent(jobNumber)}`;

  try {
    await app.client.chat.postMessage({
      channel,
      text: `📦 Please fill out the *${title}* for *${jobNumber}*:
<${link}|Contents Progress Form>`
    });

    console.log(`✅ Progress form ${progressCount} sent to ${channel}`);
    res.status(200).send('Progress form sent');
  } catch (err) {
    console.error('❌ Failed to send progress form:', err);
    res.status(500).send('Slack post failed');
  }
});

expressApp.get('/', (req, res) => res.send('Binny is alive!'));

(async () => {
  const port = process.env.PORT || 3000;
  await app.start(port);
  console.log(`⚡ Binny is running on port ${port}`);
})();
