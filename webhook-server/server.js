/**
 * NeoFreeBird Webhook Server
 *
 * Posts tweets via Twitter API v2 on behalf of the NeoFreeBird iOS client.
 * This bypasses X's attestation checks on modified clients by routing
 * tweet requests through the official API from a server context.
 *
 * Setup:
 * 1. Copy .env.example to .env and fill in your Twitter API credentials
 * 2. npm install
 * 3. npm start
 *
 * In NeoFreeBird Settings → Web API Tweeting:
 * - Enable "Web API Tweeting"
 * - Set Webhook URL to: http://your-server:3000
 * - Set API Key to match the API_KEY in your .env file
 */

require('dotenv').config();
const express = require('express');
const { TwitterApi } = require('twitter-api-v2');

const app = express();
const PORT = process.env.PORT || 3000;

// Parse JSON bodies (up to 50MB for base64 media)
app.use(express.json({ limit: '50mb' }));

// Initialize Twitter client
const twitterClient = new TwitterApi({
  appKey: process.env.TWITTER_API_KEY,
  appSecret: process.env.TWITTER_API_SECRET,
  accessToken: process.env.TWITTER_ACCESS_TOKEN,
  accessSecret: process.env.TWITTER_ACCESS_SECRET,
});

// Get read-write client
const rwClient = twitterClient.readWrite;

// API Key authentication middleware
function authenticate(req, res, next) {
  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    // No API key configured, allow all requests
    return next();
  }

  const providedKey = req.headers['x-api-key'] || '';
  const authHeader = req.headers['authorization'] || '';
  const bearerKey = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';

  if (providedKey === apiKey || bearerKey === apiKey) {
    return next();
  }

  return res.status(401).json({ error: 'Unauthorized. Invalid API key.' });
}

// Health check endpoint
app.get('/health', authenticate, (req, res) => {
  res.json({
    status: 'ok',
    message: 'NeoFreeBird webhook server is running!',
    version: '1.0.0'
  });
});

// Tweet posting endpoint
app.post('/tweet', authenticate, async (req, res) => {
  try {
    const { text, reply_to_id, quote_tweet_id, media } = req.body;

    if (!text && (!media || media.length === 0)) {
      return res.status(400).json({ error: 'Tweet text or media is required.' });
    }

    // Build tweet parameters
    const tweetParams = {};

    if (text) {
      tweetParams.text = text;
    }

    // Handle reply
    if (reply_to_id) {
      tweetParams.reply = {
        in_reply_to_tweet_id: reply_to_id
      };
    }

    // Handle quote tweet
    if (quote_tweet_id) {
      tweetParams.quote_tweet_id = quote_tweet_id;
    }

    // Handle media uploads
    if (media && media.length > 0) {
      const mediaIds = [];

      for (const mediaItem of media) {
        try {
          const buffer = Buffer.from(mediaItem.data, 'base64');
          const mimeType = mediaItem.mime_type || 'image/jpeg';

          // Upload media using v1.1 media upload endpoint
          const mediaId = await twitterClient.v1.uploadMedia(buffer, {
            mimeType: mimeType
          });
          mediaIds.push(mediaId);
        } catch (mediaError) {
          console.error('Media upload error:', mediaError);
          // Continue without this media item
        }
      }

      if (mediaIds.length > 0) {
        tweetParams.media = {
          media_ids: mediaIds
        };
      }
    }

    // Post the tweet via Twitter API v2
    const tweet = await rwClient.v2.tweet(tweetParams);

    console.log(`Tweet posted successfully! ID: ${tweet.data.id}`);

    res.json({
      success: true,
      tweet_id: tweet.data.id,
      message: `Tweet posted successfully!`
    });

  } catch (error) {
    console.error('Tweet error:', error);

    // Extract meaningful error message
    let errorMessage = 'Failed to post tweet.';
    if (error.data && error.data.detail) {
      errorMessage = error.data.detail;
    } else if (error.data && error.data.errors) {
      errorMessage = error.data.errors.map(e => e.message).join(', ');
    } else if (error.message) {
      errorMessage = error.message;
    }

    const statusCode = error.code || 500;
    res.status(statusCode).json({
      error: errorMessage
    });
  }
});

// Start server
app.listen(PORT, () => {
  console.log(`
╔══════════════════════════════════════════════════╗
║         NeoFreeBird Webhook Server v1.0          ║
╠══════════════════════════════════════════════════╣
║  Server running on port ${String(PORT).padEnd(24)}║
║  Tweet endpoint: POST /tweet                     ║
║  Health check:   GET  /health                    ║
╚══════════════════════════════════════════════════╝
  `);

  // Verify Twitter credentials on startup
  twitterClient.v2.me()
    .then(user => {
      console.log(`✅ Twitter authenticated as: @${user.data.username}`);
    })
    .catch(err => {
      console.error('⚠️  Twitter authentication failed:', err.message);
      console.error('   Please check your API credentials in .env');
    });
});
