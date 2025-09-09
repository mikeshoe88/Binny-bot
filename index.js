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

// ==== Auto-invite (auto-add) config ====
// Always add these users to every contents job channel
const ALWAYS_INVITE_USER_IDS = [
  'U07AB7A4UNS', // Anastacio
  'U086RFE5UF2', // Jennifer
  'U05FPCPHJG6', // Mike
];

// PD custom field key for Estimator
const ESTIMATOR_FIELD_KEY = '0c1e4ec54e5c4b814a6cadbf0ed473ead1dff9d4';

// Estimator name (case-insensitive) → Slack ID
const ESTIMATOR_TO_SLACK = {
  'kim':    'U05FYG3EMHS',
  'danica': 'U06DKJ1BJ9W',
  // add 'lamar': 'U086RE5K3LY' here if you want Lamar auto-added on contents jobs too
};

// Helper: normalize estimator text
function norm(s) {
  return String(s || '').trim().toLowerCase();
}

// Helper: invite users and ignore harmless errors
async function safeInvite(client, channel, userIds = []) {
  if (!channel || !userIds.length) return;
  const unique = [...new Set(userIds)].filter(Boolean);
  if (!unique.length) return;

  // Ensure bot is in the channel (public OK; private requires app already added)
  try { await client.conversations.join({ channel }); } catch (e) { /* ignore */ }

  try {
    await client.conversations.invite({ channel, users: unique.join(',') });
    console.log('[Binny] invited:', unique.join(','));
  } catch (e) {
    const err = e?.data?.error || e?.message;
    // These are fine: user already there, trying to invite the bot itself, or app lacks access to a private channel
    if (!['already_in_channel', 'cant_invite_self', 'not_in_channel'].includes(err)) {
      console.warn('[Binny] invite warning:', err);
    }
  }
}

const postedJobs = new Set();

function extractDealIdFromChannel(name) {
  const match = String(name || '').match(/deal(\d+)/i);
  return match ? match[1] : null;
}

async function runBinnyStartWorkflow(channelId, client) {
  const info = await client.conversations.info({ channel: channelId });
  const channelName = info.channel?.name || 'UNKNOWN';
  const dealId = extractDealIdFromChannel(channelName);
  const jobNumber = dealId ? channelName : 'UNKNOWN';

  let customerName = 'Customer';
  let estimatorName = null;

  if (dealId) {
    try {
      const pipedriveRes = await fetch(`https://api.pipedrive.com/v1/deals/${dealId}?api_token=${PIPEDRIVE_API_TOKEN}`);
      const dealJson = await pipedriveRes.json();
      customerName = dealJson?.data?.person_name || 'Customer';

      // Estimator may be a string or an object with { value }
      const rawEstimator = dealJson?.data?.[ESTIMATOR_FIELD_KEY];
      estimatorName =
        (rawEstimator && typeof rawEstimator === 'object' && 'value' in rawEstimator) ? rawEstimator.value :
        (typeof rawEstimator === 'string' ? rawEstimator : null);
    } catch (e) {
      console.warn('[Binny] PD deal fetch failed:', e?.message || e);
    }
  }

  // 1) Post initial contents form
  const formLink = `${INITIAL_FORM_BASE}${encodeURIComponent(jobNumber)}`;
  await client.chat.postMessage({
    channel: channelId,
    text: `📦 Please fill out the *Contents Initial Form* for *${jobNumber}*:\n<${formLink}|Contents Initial Form>`
  });

  // 2) Auto-add: baseline + estimator (if mapped)
  const toInvite = [...ALWAYS_INVITE_USER_IDS];
  const key = norm(estimatorName);
  if (key && ESTIMATOR_TO_SLACK[key]) {
    toInvite.push(ESTIMATOR_TO_SLACK[key]);
  }
  await safeInvite(client, channelId, toInvite);
}

// Auto-trigger when Binny joins a new deal channel
app.event('member_joined_channel', async ({ event, client }) => {
  // Ignore Slackbot and avoid double posts
  if (event.user === 'USLACKBOT') return;

  const channelId = event.channel;
  if (postedJobs.has(channelId)) return;

  const info = await client.conversations.info({ channel: channelId });
  const channelName = info.channel?.name || '';

  if (/deal/i.test(channelName)) {
    postedJobs.add(channelId);
    setTimeout(() => postedJobs.delete(channelId), 10000);

    // tiny delay so Slack has the channel settled
    await new Promise(r => setTimeout(r, 4000));
    await runBinnyStartWorkflow(channelId, client);
  }
});

// Manual /start command
app.command('/start', async ({ command, ack, client }) => {
  await ack();
  await runBinnyStartWorkflow(command.channel_id, client);
});

// EXPRESS SETUP
const expressApp = expressReceiver.app;
expressApp.use(express.json());

// Trigger progress form from Apps Script
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
      text: `📋 Please complete the *Contents Progress Form* for *${jobNumber}*:\n<${formLink}|Progress Form>`
    });
    console.log(`✅ Progress form posted to ${channel}`);
    res.status(200).send('Posted');
  } catch (err) {
    console.error(`❌ Failed to post progress form to ${channel}:`, err);
    res.status(500).send('Failed');
  }
});

// NEW: Final Slack message for packing complete
expressApp.post('/slack-final-message', async (req, res) => {
  const { jobNumber, message } = req.body;

  if (!jobNumber || !message) {
    return res.status(400).send('Missing jobNumber or message');
  }

  const channel = jobNumber.toLowerCase(); // e.g., "danica-deal107"

  try {
    await app.client.chat.postMessage({
      channel,
      text: `✅ ${message}`
    });

    console.log(`✅ Final Slack message posted to ${channel}`);
    return res.status(200).send('Message sent to Slack');
  } catch (err) {
    console.error(`❌ Failed to post final Slack message to ${channel}:`, err);
    return res.status(500).send('Slack message failed');
  }
});

// Alive ping
expressApp.get('/', (req, res) => res.send('Binny is alive!'));

// Start server
(async () => {
  const port = process.env.PORT || 3000;
  await app.start(port);
  console.log(`⚡ Binny running on port ${port}`);
})();
