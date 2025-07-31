// Binny Slack Bot - For Contents Jobs (Initial + Progress Form Logic)
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

const INITIAL_FORM_BASE = 'https://docs.google.com/forms/d/e/1FAIpQLScOHXE_h7gr_kagnUy-xTtV_gJsyTAMl7NtjlV4OBA1yPsZzw/viewform?usp=pp_url&entry.1514728493=';
const PROGRESS_FORM_BASE = 'https://docs.google.com/forms/d/e/1FAIpQLSck9PRgRSGHWWgqIy0UJDC6r51Ihv5TIFKBILs-_sEzrkY7PA/viewform?usp=pp_url&entry.1942941566=';
const PIPEDRIVE_API_TOKEN = process.env.PIPEDRIVE_API_TOKEN;
const postedJobs = new Set();

function extractDealIdFromChannel(name) {
  const match = name.match(/deal(\d+)/);
  return match ? match[1] : null;
}

async function runBinnyStartWorkflow(channelId, client) {
  const info = await client.conversations.info({ channel: channelId });
  const channelName = info.channel?.name || 'UNKNOWN';
  const dealId = extractDealIdFromChannel(channelName);
  const jobNumber = dealId ? channelName : 'UNKNOWN';

  let customerName = 'Customer';
  if (dealId) {
    const pipedriveRes = await fetch(`https://api.pipedrive.com/v1/deals/${dealId}?api_token=${PIPEDRIVE_API_TOKEN}`);
    const dealData = await pipedriveRes.json();
    customerName = dealData?.data?.person_name || 'Customer';
  }

  const formLink = `${INITIAL_FORM_BASE}${encodeURIComponent(jobNumber)}`;

  await client.chat.postMessage({
    channel: channelId,
    text: `📦 Please fill out the *Contents Initial Form* for *${jobNumber}*:
<${formLink}|Contents Initial Form>`
  });
}

app.event('member_joined_channel', async ({ event, client }) => {
  if (event.user === 'USLACKBOT') return;

  const channelId = event.channel;
  if (postedJobs.has(channelId)) return;

  const info = await client.conversations.info({ channel: channelId });
  const channelName = info.channel?.name || '';

  if (channelName.includes('deal')) {
    postedJobs.add(channelId);
    setTimeout(() => postedJobs.delete(channelId), 10000);

    await new Promise(r => setTimeout(r, 4000));
    await runBinnyStartWorkflow(channelId, client);
  }
});

app.command('/start', async ({ command, ack, client }) => {
  await ack();
  await runBinnyStartWorkflow(command.channel_id, client);
});

const expressApp = expressReceiver.app;
expressApp.use(express.json());

expressApp.post('/trigger-progress-form', async (req, res) => {
  const jobNumber = req.body?.jobNumber;
  if (!jobNumber || !jobNumber.toLowerCase().includes('deal')) {
    return res.status(400).send('Invalid job number');
  }
  const channel = jobNumber.toLowerCase();
  const formLink = `${PROGRESS_FORM_BASE}${encodeURIComponent(jobNumber)}`;

  try {
    await app.client.chat.postMessage({
      channel,
      text: `📋 Please complete the *Contents Progress Form* for *${jobNumber}*:
<${formLink}|Progress Form>`
    });
    console.log(`✅ Progress form posted to ${channel}`);
    res.status(200).send('Posted');
  } catch (err) {
    console.error(`❌ Failed to post progress form to ${channel}:`, err);
    res.status(500).send('Failed');
  }
});

expressApp.get('/', (req, res) => res.send('Binny is alive!'));

(async () => {
  const port = process.env.PORT || 3000;
  await app.start(port);
  console.log(`⚡ Binny running on port ${port}`);
})();
