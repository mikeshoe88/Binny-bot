// Binny - Contents Bot (starter)
const { App, ExpressReceiver } = require('@slack/bolt');
const express = require('express');
const fetch = (...args) => import('node-fetch').then(({ default: fetch }) => fetch(...args));

const expressReceiver = new ExpressReceiver({
  signingSecret: process.env.SLACK_SIGNING_SECRET,
  endpoints: '/slack/events',
  processBeforeResponse: true,
  bodyParser: false,
});

const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  signingSecret: process.env.SLACK_SIGNING_SECRET,
  receiver: expressReceiver,
});

const expressApp = expressReceiver.app;

expressApp.get('/', (req, res) => res.send('Binny is online!'));

// Example command or event handler here...

(async () => {
  const port = process.env.PORT || 3000;
  await app.start(port);
  console.log(`📦 Binny is running on port ${port}`);
})();
